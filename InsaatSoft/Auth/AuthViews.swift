import SwiftUI
import UIKit

// MARK: - Ortak görünüm

/// Giriş ekranlarının lacivert zemini ve logo
struct GirisZemini<Icerik: View>: View {
    @ViewBuilder let icerik: () -> Icerik

    var body: some View {
        ZStack {
            LinearGradient(colors: [Tema.lacivert, Tema.lacivert2], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image("Logo").resizable().scaledToFit().frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        Text(Store.firmaAd ?? Config.appName).font(.title2.weight(.bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        Text("Şantiyeden finansa tek panel").font(.subheadline).foregroundStyle(Tema.altin)
                    }
                    .padding(.top, 40)
                    icerik()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }
}

struct GirisAlani: View {
    let baslik: String
    @Binding var metin: String
    var gizli = false
    var klavye: UIKeyboardType = .default
    var icerik: UITextContentType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(baslik).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Group {
                if gizli { SecureField("", text: $metin) } else { TextField("", text: $metin) }
            }
            .keyboardType(klavye)
            .textContentType(icerik)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
            .foregroundStyle(.white)
        }
    }
}

struct AnaDugme: View {
    let baslik: String
    var calisiyor = false
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            HStack {
                Spacer()
                if calisiyor { ProgressView().tint(Tema.lacivert) } else { Text(baslik).fontWeight(.semibold) }
                Spacer()
            }
            .padding(.vertical, 14)
            .foregroundStyle(Tema.lacivert)
            .background(Tema.altin, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(calisiyor)
    }
}

struct HataKutusu: View {
    let metin: String
    var renk: Color = Color(hex: "#ff8a80")
    var body: some View {
        Text(metin).font(.subheadline).foregroundStyle(renk).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(renk.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Firma No

struct FirmaView: View {
    @EnvironmentObject private var session: Session
    @State private var no = Store.firmaNo ?? ""
    @State private var adres = ""
    @State private var elle = false
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        GirisZemini {
            VStack(spacing: 16) {
                Text("Firmanıza bağlanmak için yöneticinizin verdiği Firma No'yu girin.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                if !elle {
                    GirisAlani(baslik: "FİRMA NO", metin: $no)
                } else {
                    GirisAlani(baslik: "PROGRAM ADRESİ", metin: $adres, klavye: .URL, icerik: .URL)
                    Text("Örnek: https://firmaniz.kaviscloud.com").font(.caption).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
                    GirisAlani(baslik: "FİRMA NO (varsa)", metin: $no)
                }
                if let h = hata { HataKutusu(metin: h) }
                AnaDugme(baslik: "Devam", calisiyor: calisiyor) { Task { await devam() } }
                Button(elle ? "Firma No ile bağlan" : "Program adresiyle bağlan") { withAnimation { elle.toggle(); hata = nil } }
                    .font(.footnote).foregroundStyle(Tema.altin)
            }
        }
    }

    private func devam() async {
        hata = nil
        calisiyor = true
        defer { calisiyor = false }
        if elle {
            var a = adres.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.lowercased().hasPrefix("http") { a = "https://" + a }
            while a.hasSuffix("/") { a.removeLast() }
            guard let u = URL(string: a), u.scheme == "https", let host = u.host, host.contains(".") else {
                hata = "Geçerli bir https adresi yazın."
                return
            }
            Store.firmaURL = a
            Store.firmaAd = host
            Store.firmaNo = no.trimmingCharacters(in: .whitespaces)
            session.asama = .giris
            return
        }
        let n = no.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { hata = "Firma No'yu girin."; return }
        do {
            let f = try await KavisCloud.firmaBul(n)
            if f.surum.zorunluGuncelleme {
                session.asama = .guncelle(.init(surum: f.surum.guncel, adres: f.surum.indirme))
                return
            }
            Store.firmaURL = f.url
            Store.firmaAd = f.ad
            Store.firmaNo = f.firmaNo
            session.asama = .giris
        } catch {
            hata = error.localizedDescription
        }
    }
}

// MARK: - Giriş (parola + Google Authenticator)

@MainActor
final class GirisModel: ObservableObject {
    enum Adim: Equatable { case parola, tfa, kurulum(gizli: String, uri: String, hesap: String) }

    @Published var adim: Adim = .parola
    @Published var email = Store.sonEmail ?? ""
    @Published var parola = ""
    @Published var kod = ""
    @Published var hata: String?
    @Published var bilgi: String?
    @Published var calisiyor = false
    @Published var yedekKodlar: [String] = []
    private var bekleyenParolaDegistir = false

    func giris(_ session: Session) async {
        hata = nil
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !e.isEmpty, !parola.isEmpty else { hata = "E-posta ve parolanızı girin."; return }
        if adim != .parola, kod.filter({ $0.isLetter || $0.isNumber }).count < 6 { hata = "Doğrulama kodunu girin."; return }
        calisiyor = true
        defer { calisiyor = false }
        var alan: [(String, String)] = [
            ("firma_no", Store.firmaNo ?? ""), ("email", e), ("parola", parola),
            ("cihaz_kimlik", Keychain.cihazKimlik), ("cihaz_adi", Config.deviceName), ("platform", "ios"),
            ("uygulama_surum", Config.appVersion),
        ]
        if let s = Keychain.cihazSirri { alan.append(("cihaz_sirri", s)) }
        if adim != .parola { alan.append(("kod", kod.filter { $0.isLetter || $0.isNumber })) }
        if case .kurulum = adim { alan.append(("kurulum", "1")) }
        do {
            let (j, _) = try await API.shared.ham("giris", govde: .form(alan), kimlik: false)
            if j["ok"].bool {
                API.shared.anahtarlariKaydet(j)
                Store.sonEmail = e
                parola = ""
                kod = ""
                if j["biyometrik"].bool && Biometric.anahtarVar { Store.biyometrikAcik = true }
                session.kullanici = j["kullanici"]
                bekleyenParolaDegistir = j["parola_degistir"].bool
                let yedek = j["yedek_kodlar"].stringArray
                if !yedek.isEmpty { yedekKodlar = yedek; return }   // önce yedek kodlar gösterilir
                await tamamla(session)
                return
            }
            let msg = j.str("msg") ?? "Giriş yapılamadı."
            switch j["kod"].string {
            case "tfa":
                adim = .tfa; bilgi = msg; kod = ""
            case "tfa_kurulum_basla":
                adim = .kurulum(gizli: j["gizli"].string, uri: j["uri"].string, hesap: j["hesap"].string); bilgi = msg; kod = ""
            case "tfa_hatali":
                hata = msg; kod = ""
            default:
                hata = msg
                if j["kod"].string == "hatali" { adim = .parola }
            }
        } catch {
            hata = error.localizedDescription
        }
    }

    func tamamla(_ session: Session) async {
        yedekKodlar = []
        if !Store.biyometrikAcik && Biometric.kullanilabilir && !Store.biyometrikSoruldu { session.biyometrikTeklif = true }
        await session.girisTamam(parolaDegistir: bekleyenParolaDegistir)
    }

    func geri() { adim = .parola; kod = ""; bilgi = nil; hata = nil }
}

struct GirisView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var vm = GirisModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        GirisZemini {
            VStack(spacing: 16) {
                if let b = session.bilgi, vm.hata == nil, vm.adim == .parola { HataKutusu(metin: b, renk: Tema.altin) }
                switch vm.adim {
                case .parola:
                    GirisAlani(baslik: "E-POSTA", metin: $vm.email, klavye: .emailAddress, icerik: .username)
                    GirisAlani(baslik: "PAROLA", metin: $vm.parola, gizli: true, icerik: .password)
                case .tfa:
                    if let b = vm.bilgi { Text(b).font(.subheadline).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center) }
                    GirisAlani(baslik: "DOĞRULAMA KODU", metin: $vm.kod, klavye: .numberPad, icerik: .oneTimeCode)
                    Text("Google Authenticator'daki 6 haneli kodu ya da 8 haneli yedek kodlarınızdan birini girin.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity, alignment: .leading)
                case .kurulum(let gizli, let uri, _):
                    if let b = vm.bilgi { Text(b).font(.subheadline).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center) }
                    VStack(spacing: 10) {
                        Text("KURULUM ANAHTARI").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Text(gizli).font(.system(.title3, design: .monospaced).weight(.semibold)).foregroundStyle(Tema.altin)
                            .multilineTextAlignment(.center).textSelection(.enabled)
                        HStack {
                            Button { UIPasteboard.general.string = gizli.replacingOccurrences(of: " ", with: ""); Toast.shared.goster("Anahtar kopyalandı.") } label: {
                                Label("Kopyala", systemImage: "doc.on.doc")
                            }
                            if let u = URL(string: uri) {
                                Button { openURL(u) } label: { Label("Authenticator'a ekle", systemImage: "plus.app") }
                            }
                        }
                        .buttonStyle(.bordered).tint(Tema.altin).font(.subheadline)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    GirisAlani(baslik: "UYGULAMADAKİ 6 HANELİ KOD", metin: $vm.kod, klavye: .numberPad, icerik: .oneTimeCode)
                }
                if let h = vm.hata { HataKutusu(metin: h) }
                AnaDugme(baslik: vm.adim == .parola ? "Giriş yap" : "Doğrula", calisiyor: vm.calisiyor) { Task { await vm.giris(session) } }
                if vm.adim != .parola {
                    Button("Geri") { vm.geri() }.font(.footnote).foregroundStyle(.white.opacity(0.7))
                }
                if vm.adim == .parola {
                    if Store.biyometrikAcik && Biometric.anahtarVar {
                        Button { session.asama = .kilitli } label: { Label("\(Biometric.ad) ile giriş", systemImage: Biometric.simge) }
                            .font(.subheadline.weight(.medium)).foregroundStyle(Tema.altin)
                    }
                    Button("Firmayı değiştir") { session.firmayiDegistir() }
                        .font(.footnote).foregroundStyle(.white.opacity(0.6)).padding(.top, 6)
                }
            }
        }
        .sheet(isPresented: Binding(get: { !vm.yedekKodlar.isEmpty }, set: { _ in })) {
            YedekKodlarView(kodlar: vm.yedekKodlar) { Task { await vm.tamamla(session) } }
                .interactiveDismissDisabled()
        }
    }
}

struct YedekKodlarView: View {
    let kodlar: [String]
    let devam: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(kodlar, id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
                } footer: {
                    Text("Telefonunuza erişemezseniz bu kodlarla giriş yapabilirsiniz. Her kod bir kez kullanılır. Güvenli bir yere kaydedin; bu kodlar bir daha gösterilmez.")
                }
                Section {
                    Button { UIPasteboard.general.string = kodlar.joined(separator: "\n"); Toast.shared.goster("Kodlar kopyalandı.") } label: {
                        Label("Kodları kopyala", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: kodlar.joined(separator: "\n")) { Label("Paylaş / kaydet", systemImage: "square.and.arrow.up") }
                }
            }
            .navigationTitle("Yedek kodlar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kaydettim", action: devam).fontWeight(.semibold) } }
        }
    }
}

// MARK: - Face ID kilidi

struct KilitView: View {
    @EnvironmentObject private var session: Session
    @State private var hata: String?
    @State private var calisiyor = false
    @State private var denendi = false

    var body: some View {
        GirisZemini {
            VStack(spacing: 18) {
                Image(systemName: Biometric.simge).font(.system(size: 56)).foregroundStyle(Tema.altin).padding(.top, 10)
                if let h = hata { HataKutusu(metin: h) }
                AnaDugme(baslik: "\(Biometric.ad) ile giriş", calisiyor: calisiyor) { Task { await ac() } }
                Button("Parola ile giriş") { session.asama = .giris }.font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }
        .task {
            guard !denendi else { return }
            denendi = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            await ac()
        }
    }

    private func ac() async {
        hata = nil
        calisiyor = true
        defer { calisiyor = false }
        do { try await session.biyometrikGiris() } catch let e as APIError {
            if e.kod != "iptal" { hata = e.msg }
            if e.kod == "biyometrik_yok" || e.kod == "imza" || e.kod == "cikarildi" || e.kod == "tfa" { session.asama = .giris; session.bilgi = e.msg }
        } catch { hata = error.localizedDescription }
    }
}

// MARK: - Parola değiştirme (KavisCloud geçici parolası)

struct ParolaDegistirView: View {
    @EnvironmentObject private var session: Session
    @State private var yeni = ""
    @State private var yeni2 = ""
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        GirisZemini {
            VStack(spacing: 16) {
                Text("Devam etmeden önce yeni bir parola belirleyin.").font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("En az 10 karakter; büyük harf, küçük harf, rakam ve işaret önerilir.").font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                GirisAlani(baslik: "YENİ PAROLA", metin: $yeni, gizli: true, icerik: .newPassword)
                GirisAlani(baslik: "YENİ PAROLA (TEKRAR)", metin: $yeni2, gizli: true, icerik: .newPassword)
                if let h = hata { HataKutusu(metin: h) }
                AnaDugme(baslik: "Parolayı değiştir", calisiyor: calisiyor) { Task { await kaydet() } }
                Button("Çıkış yap") { Task { await session.cikis() } }.font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func kaydet() async {
        hata = nil
        guard !yeni.isEmpty, yeni == yeni2 else { hata = "Yeni parolalar eşleşmiyor."; return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let j = try await API.shared.cagir("parola_degistir", govde: .form([("yeni", yeni), ("yeni2", yeni2)]))
            Toast.shared.goster(j.str("msg") ?? "Parolanız değiştirildi.")
            await session.girisTamam()
        } catch { hata = error.localizedDescription }
    }
}

// MARK: - Engel / güncelleme

struct EngelView: View {
    let mesaj: String
    @EnvironmentObject private var session: Session
    var body: some View {
        GirisZemini {
            VStack(spacing: 16) {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill").font(.system(size: 48)).foregroundStyle(Tema.altin)
                Text(mesaj).foregroundStyle(.white).multilineTextAlignment(.center)
                AnaDugme(baslik: "Tekrar dene") { session.asama = .aciliyor; Task { await session.baslat() } }
                Button("Firmayı değiştir") { session.firmayiDegistir() }.font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

struct GuncelleView: View {
    let bilgi: Session.KavisGuncelleme
    @Environment(\.openURL) private var openURL
    var body: some View {
        GirisZemini {
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.app.fill").font(.system(size: 52)).foregroundStyle(Tema.altin)
                Text("Uygulamanın yeni sürümü gerekli").font(.headline).foregroundStyle(.white)
                Text("Devam etmek için uygulamayı \(bilgi.surum.isEmpty ? "son sürüme" : "\(bilgi.surum) sürümüne") güncelleyin. Kullandığınız sürüm: \(Config.appVersion)")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                if let u = URL(string: bilgi.adres), !bilgi.adres.isEmpty {
                    AnaDugme(baslik: "App Store'da güncelle") { openURL(u) }
                }
            }
        }
    }
}
