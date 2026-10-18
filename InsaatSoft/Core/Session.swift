import Foundation
import SwiftUI
import UIKit

/// Uygulamanın durumu: firma seçimi → giriş → (parola değiştirme) → ana ekran.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()

    enum Asama: Equatable {
        case aciliyor
        case firma
        case giris
        case kilitli            // Face ID ile açılacak
        case parolaDegistir
        case hazir
        case engelli(String)
        case guncelle(KavisGuncelleme)
    }

    struct KavisGuncelleme: Equatable { let surum: String; let adres: String }

    @Published var asama: Asama = .aciliyor {
        didSet { if let z = zorunluGuncelleme, asama != .guncelle(z) { asama = .guncelle(z) } }
    }
    private var zorunluGuncelleme: KavisGuncelleme?
    @Published var menu: JSON = .null
    @Published var kullanici: JSON = .null
    @Published var bilgi: String?               // giriş ekranında gösterilecek mesaj (oturum bitti vb.)
    @Published var okunmamis = 0
    @Published var sohbetOkunmamis = 0
    @Published var yeniSurum: KavisCloud.SurumBilgisi?
    @Published var popuplar: [JSON] = []
    @Published var destekDaveti = false
    @Published var biyometrikTeklif = false     // girişten sonra "Face ID ile giriş açılsın mı?"

    private var arkaPlanZamani: Date?

    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .oturumBitti, object: nil, queue: .main) { n in
            let m = n.object as? String
            Task { @MainActor in Session.shared.oturumBitti(m) }
        }
        nc.addObserver(forName: .erisimEngellendi, object: nil, queue: .main) { n in
            let m = (n.object as? String) ?? "Erişim kapatıldı."
            Task { @MainActor in Session.shared.engelle(m) }
        }
        nc.addObserver(forName: .parolaDegistirmeli, object: nil, queue: .main) { _ in
            Task { @MainActor in if Session.shared.asama == .hazir { Session.shared.asama = .parolaDegistir } }
        }
    }

    var firmaAd: String { menu.str("firma") ?? Store.firmaAd ?? Config.appName }

    // MARK: Açılış

    func baslat() async {
        // Sürüm denetimi açılışı bekletmez; zorunlu güncelleme varsa hangi ekranda olunursa olunsun güncelleme ekranı açılır
        Task {
            guard let s = await KavisCloud.surumDenetle() else { return }
            if s.zorunluGuncelleme {
                Notifier.shared.durdur()
                let g = KavisGuncelleme(surum: s.guncel, adres: s.indirme)
                zorunluGuncelleme = g
                asama = .guncelle(g)
            }
            else if s.yeniSurumVar { yeniSurum = s }
        }
        guard Store.firmaURL != nil else { asama = .firma; return }
        if Store.biyometrikAcik && Biometric.anahtarVar { asama = .kilitli; return }
        guard Keychain.yenileme != nil else { asama = .giris; return }
        switch await API.shared.oturumuYenile() {
        case .tamam: await girisTamam()
        case .reddedildi(let m): bilgi = m; asama = .giris
        case .ag:
            // Çevrimdışı: eldeki erişim anahtarıyla dene, olmazsa giriş ekranı
            if Keychain.erisim != nil { await girisTamam() } else { bilgi = "Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin."; asama = .giris }
        }
    }

    /// Başarılı giriş / yenileme sonrası
    func girisTamam(parolaDegistir: Bool = false) async {
        bilgi = nil
        if parolaDegistir { asama = .parolaDegistir; return }
        await menuYukle()
        if case .engelli = asama { return }
        if asama == .parolaDegistir { return }
        asama = .hazir
        Notifier.shared.baslat()
        await duyurulariAl()
    }

    func menuYukle() async {
        do {
            let j = try await API.shared.cagir("menu")
            menu = j
            kullanici = j["kullanici"]
            if let f = j.str("firma") { Store.firmaAd = f }
        } catch let e as APIError {
            if e.kod == "parola_degistir" { asama = .parolaDegistir }
            else if menu.isNull { bilgi = e.msg }
        } catch {}
    }

    // MARK: Uygulama yaşam döngüsü

    func arkaPlanaGecti() {
        arkaPlanZamani = Date()
        Notifier.shared.durdur()
    }

    func onPlanaGeldi() {
        defer { arkaPlanZamani = nil }
        guard asama == .hazir else { return }
        if let z = arkaPlanZamani, Date().timeIntervalSince(z) > Config.relockAfter, Store.biyometrikAcik, Biometric.anahtarVar {
            asama = .kilitli
            return
        }
        Notifier.shared.baslat()
        Task { await duyurulariAl() }
    }

    // MARK: Çıkış / engel

    func cikis() async {
        _ = try? await API.shared.ham("cikis", govde: .form([]))
        yerelCikis(nil)
    }

    func yerelCikis(_ mesaj: String?) {
        Notifier.shared.durdur()
        Keychain.oturumuSil()
        API.shared.onbellegiTemizle()
        menu = .null
        kullanici = .null
        okunmamis = 0
        sohbetOkunmamis = 0
        bilgi = mesaj
        asama = Store.firmaURL == nil ? .firma : .giris   // Face ID açıksa giriş ekranında "Face ID ile giriş" düğmesi görünür
    }

    func firmayiDegistir() {
        Notifier.shared.durdur()
        Keychain.hepsiniSil()
        Biometric.anahtariSil()
        Store.firmayiUnut()
        menu = .null
        kullanici = .null
        bilgi = nil
        asama = .firma
    }

    private func oturumBitti(_ m: String?) {
        guard asama == .hazir || asama == .parolaDegistir else { return }
        yerelCikis(m ?? "Oturumunuz sona erdi, yeniden giriş yapın.")
    }

    private func engelle(_ m: String) {
        Notifier.shared.durdur()
        Keychain.oturumuSil()
        asama = .engelli(m)
    }

    // MARK: Face ID

    /// Kilitli ekrandan: sunucudan meydan okuma al, Face ID ile imzala, oturum aç
    func biyometrikGiris() async throws {
        let ck = Keychain.cihazKimlik
        let (m, _) = try await API.shared.ham("biyometrik/meydan", govde: .form([("cihaz_kimlik", ck)]), kimlik: false)
        guard m["ok"].bool, let meydan = m.str("meydan") else {
            if m["kod"].string == "biyometrik_yok" { biyometrikKapatYerel() }
            if m["kod"].string == "cihaz_engel" { engelle(m.str("msg") ?? "Erişim kapatıldı.") }
            throw APIError(kod: m["kod"].string, msg: m.str("msg") ?? "Doğrulama başlatılamadı.")
        }
        let imza = try await Biometric.imzala(meydan, neden: "\(firmaAdKisa) hesabınıza giriş yapın")
        let (j, _) = try await API.shared.ham("biyometrik/giris", govde: .form([("cihaz_kimlik", ck), ("imza", imza)]), kimlik: false)
        guard j["ok"].bool else {
            let kod = j["kod"].string
            if kod == "imza" || kod == "biyometrik_yok" || kod == "cikarildi" || kod == "tfa" { biyometrikKapatYerel() }
            if kod == "cihaz_engel" { engelle(j.str("msg") ?? "Erişim kapatıldı.") }
            throw APIError(kod: kod, msg: j.str("msg") ?? "Giriş yapılamadı.")
        }
        API.shared.anahtarlariKaydet(j)
        kullanici = j["kullanici"]
        await girisTamam()
    }

    private var firmaAdKisa: String { Store.firmaAd ?? Config.appName }

    func biyometrikAc() async throws {
        let anahtar = try Biometric.anahtarUret()
        do {
            try await API.shared.cagir("biyometrik/kaydet", govde: .form([("acik_anahtar", anahtar)]))
            Store.biyometrikAcik = true
        } catch {
            Biometric.anahtariSil()
            throw error
        }
    }

    func biyometrikKapat() async {
        _ = try? await API.shared.cagir("biyometrik/kapat", govde: .form([]))
        biyometrikKapatYerel()
    }

    private func biyometrikKapatYerel() {
        Biometric.anahtariSil()
        Store.biyometrikAcik = false
    }

    // MARK: KavisCloud duyuruları

    func duyurulariAl() async {
        guard asama == .hazir else { return }
        guard let j = try? await API.shared.cagir("duyurular", govde: .json(["seen": Store.gorulenPopup])) else { return }
        let gorulen = Set(Store.gorulenPopup)
        let yeni = j["popups"].array.filter { $0["id"].int > 0 && !gorulen.contains($0["id"].int) }
        if !yeni.isEmpty { popuplar = yeni }
        if j["davet"].bool { destekDaveti = true }
    }

    func popupGoruldu(_ p: JSON) {
        var g = Store.gorulenPopup
        g.append(p["id"].int)
        Store.gorulenPopup = g
        popuplar.removeAll { $0["id"].int == p["id"].int }
    }
}
