import Foundation
import SwiftUI
import UIKit

/// Gezinme hedefleri. Ekran / form kimlikleri sunucunun verdiği biçimdedir ("f:projeler:0", "musteri|id=5" …)
enum Route: Hashable {
    case ekran(String)
    case form(String, kayit: Int)
    case sohbet(kanal: String, ad: String)
    case destek
    case tani
}

/// Sekme seçimi ve bildirimden açılan ekranlar
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    enum Sekme: Hashable { case genel, menu, bildirim, sohbet, hesap }

    @Published var sekme: Sekme = .genel
    @Published var sayfa: SayfaHedef?

    struct SayfaHedef: Identifiable { let id = UUID(); let route: Route }

    func bildirimdenAc(_ ekran: String) {
        guard Session.shared.asama == .hazir else { return }
        if ekran == "bildirimler" { sekme = .bildirim; return }
        sayfa = SayfaHedef(route: .ekran(ekran))
    }

    func ac(_ r: Route) { sayfa = SayfaHedef(route: r) }
}

/// Sunucunun ekran tanımlarındaki dokunma hedefi / işlem düğmesi:
/// {etiket, ikon, renk, ekran | form(+kayit) | istek(+onay, geri) | tel | wa | url | eposta | kopya | paylas(+dosya_adi)}
/// "url" sunucunun imzalı indirme adresiyse (r=indir) dosya uygulama içinde açılır (önizleme, paylaş, yazdır).
struct Eylem: Identifiable {
    let id = UUID()
    let etiket: String
    let ikon: String
    let renk: String
    let ekran: String?
    let form: String?
    let kayit: Int
    let istek: String?
    let onay: String?
    let geri: Bool
    let tel: String?
    let wa: String?
    let url: String?
    let eposta: String?
    let kopya: String?
    let paylas: String?
    let dosyaAdi: String

    init?(_ j: JSON) {
        guard j.isObject else { return nil }
        etiket = j["etiket"].string
        ikon = j["ikon"].string
        renk = j["renk"].string
        ekran = j.str("ekran")
        form = j.str("form")
        kayit = j["kayit"].int
        istek = j.str("istek")
        onay = j.str("onay")
        geri = j["geri"].bool
        tel = j.str("tel")
        wa = j.str("wa")
        url = j.str("url")
        eposta = j.str("eposta")
        kopya = j.str("kopya")
        paylas = j.str("paylas")
        dosyaAdi = j.str("dosya_adi") ?? "dosya.txt"
        if ekran == nil, form == nil, istek == nil, tel == nil, wa == nil, url == nil, eposta == nil, kopya == nil, paylas == nil { return nil }
    }

    static func liste(_ j: JSON) -> [Eylem] { j.array.compactMap { Eylem($0) } }

    var route: Route? {
        if let f = form { return .form(f, kayit: kayit) }
        if let e = ekran { return .ekran(e) }
        return nil
    }

    /// Sunucunun imzalı indirme adresi (dosya, CSV, e-belge XML, yedek): uygulama içinde indirilip önizlenir
    var indirme: URL? {
        guard let u = url, u.contains("r=indir"), u.hasPrefix("http"), let adres = API.shared.mutlak(u) else { return nil }
        return adres
    }

    var disAdres: URL? {
        if let t = tel { return URL(string: "tel:" + t.filter { $0.isNumber || $0 == "+" }) }
        if let w = wa { return Eylem.whatsapp(w) }
        if let e = eposta { return URL(string: "mailto:" + e) }
        if let u = url { return URL(string: u) }
        return nil
    }

    /// Türkiye numaraları: 05xx… / 5xx… → 905xx…
    static func whatsapp(_ tel: String) -> URL? {
        var d = tel.filter(\.isNumber)
        if d.hasPrefix("00") { d.removeFirst(2) }
        if d.hasPrefix("0") { d.removeFirst() }
        if d.count == 10 { d = "90" + d }
        return URL(string: "https://wa.me/" + d)
    }

    var silme: Bool { renk == "red" || ikon.contains("trash") }
}
