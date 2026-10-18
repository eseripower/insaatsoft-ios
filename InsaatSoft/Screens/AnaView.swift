import SwiftUI
import UIKit

/// Giriş yapıldıktan sonraki ana ekran: sekmeler
struct AnaView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var router: Router

    var body: some View {
        TabView(selection: $router.sekme) {
            Yigin { EkranView(id: "panel", kok: true) }
                .tabItem { Label("Genel Bakış", systemImage: "chart.pie.fill") }
                .tag(Router.Sekme.genel)
            Yigin { MenuView() }
                .tabItem { Label("Menü", systemImage: "square.grid.2x2.fill") }
                .tag(Router.Sekme.menu)
            Yigin { EkranView(id: "bildirimler", kok: true) }
                .tabItem { Label("Bildirimler", systemImage: "bell.fill") }
                .badge(session.okunmamis)
                .tag(Router.Sekme.bildirim)
            Yigin { SohbetListeView() }
                .tabItem { Label("Sohbet", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(session.sohbetOkunmamis)
                .tag(Router.Sekme.sohbet)
            Yigin { HesapView() }
                .tabItem { Label("Hesabım", systemImage: "person.crop.circle.fill") }
                .tag(Router.Sekme.hesap)
        }
        .sheet(item: $router.sayfa) { SayfaKabi(route: $0.route) }
        .sheet(item: Binding(get: { session.popuplar.first.map { PopupKimlik(j: $0) } }, set: { _ in })) { p in
            PopupView(j: p.j) { session.popupGoruldu(p.j) }
        }
        .alert("\(Biometric.ad) ile giriş", isPresented: $session.biyometrikTeklif) {
            Button("Aç") {
                Store.biyometrikSoruldu = true
                Task {
                    do { try await session.biyometrikAc(); Toast.shared.goster("\(Biometric.ad) ile giriş açıldı.") }
                    catch { Toast.shared.goster(error.localizedDescription, hata: true) }
                }
            }
            Button("Şimdi değil", role: .cancel) { Store.biyometrikSoruldu = true }
        } message: {
            Text("Sonraki girişlerinizde parola yerine \(Biometric.ad) kullanılsın mı? Yüz / parmak izi bilginiz telefondan çıkmaz.")
        }
        .alert("Canlı destek", isPresented: $session.destekDaveti) {
            Button("Sohbeti aç") { router.ac(.destek) }
            Button("Kapat", role: .cancel) {}
        } message: { Text("Destek ekibi sizi canlı sohbete davet ediyor.") }
    }
}

private struct PopupKimlik: Identifiable { let j: JSON; var id: Int { j["id"].int } }

/// KavisCloud'dan gönderilen pop-up duyuru
struct PopupView: View {
    let j: JSON
    let kapat: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let r = j.str("resim") { DuzResim(kaynak: r).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    Text(j["metin"].string).font(.body)
                    if let b = j["dugme"].str("url"), let u = URL(string: b) {
                        Button { openURL(u) } label: {
                            Text(j["dugme"].str("text") ?? "Aç").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent).tint(Tema.altin)
                    }
                }
                .padding(20)
            }
            .navigationTitle(j.str("baslik") ?? "Duyuru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { kapat() }
    }
}

/// Hesap: profil, parola, Face ID, destek, tanılama, çıkış
struct HesapView: View {
    @EnvironmentObject private var session: Session
    @State private var biyometrik = Store.biyometrikAcik && Biometric.anahtarVar
    @State private var cikisSor = false
    @State private var firmaSor = false

    var body: some View {
        let k = session.kullanici.isNull ? session.menu["kullanici"] : session.kullanici
        List {
            Section {
                HStack(spacing: 14) {
                    if let r = k.str("resim") {
                        YetkiliResim(adres: r).frame(width: 56, height: 56).clipShape(Circle())
                    } else {
                        Text(String(k["adsoyad"].string.prefix(1))).font(.title2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 56, height: 56).background(Tema.altin.gradient, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k["adsoyad"].string).font(.headline)
                        Text(k["email"].string).font(.subheadline).foregroundStyle(.secondary)
                        Text(k["rol"].string == "admin" ? "Yönetici" : "Personel").font(.caption).foregroundStyle(Tema.altin)
                    }
                }
                .padding(.vertical, 4)
                NavigationLink(value: Route.ekran("profil")) { Label("Profilim", systemImage: "person.text.rectangle") }
                NavigationLink(value: Route.form("parola", kayit: 0)) { Label("Parolamı değiştir", systemImage: "key") }
            }

            Section {
                if Biometric.kullanilabilir {
                    Toggle(isOn: Binding(get: { biyometrik }, set: { yeni in
                        Task {
                            if yeni {
                                do { try await session.biyometrikAc(); biyometrik = true; Toast.shared.goster("\(Biometric.ad) ile giriş açıldı.") }
                                catch { biyometrik = false; Toast.shared.goster(error.localizedDescription, hata: true) }
                            } else {
                                await session.biyometrikKapat(); biyometrik = false
                            }
                        }
                    })) { Label("\(Biometric.ad) ile giriş", systemImage: Biometric.simge) }
                    .tint(Tema.altin)
                }
                Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                    Label("Bildirim izinleri", systemImage: "bell.badge")
                }
            } header: { Text("Güvenlik ve bildirimler") }

            Section("Firma") {
                LabeledContent("Firma", value: session.firmaAd)
                if let no = session.menu.str("firma_no") ?? Store.firmaNo { LabeledContent("Firma No", value: no) }
                LabeledContent("Program", value: "\(session.menu["program"].string) \(session.menu["surum"].string)")
                if session.menu["destek"].bool {
                    NavigationLink(value: Route.destek) { Label("Canlı destek", systemImage: "headphones") }
                }
                NavigationLink(value: Route.tani) { Label("Bağlantı tanılama", systemImage: "stethoscope") }
            }

            if let y = session.yeniSurum, let u = URL(string: y.indirme), !y.indirme.isEmpty {
                Section {
                    Link(destination: u) { Label("Yeni sürüm var: \(y.guncel) — App Store'da güncelle", systemImage: "arrow.down.app") }
                }
            }

            Section {
                Button(role: .destructive) { cikisSor = true } label: { Label("Çıkış yap", systemImage: "rectangle.portrait.and.arrow.right") }
                Button(role: .destructive) { firmaSor = true } label: { Label("Firmayı değiştir", systemImage: "building.2") }
            } footer: {
                Text("\(Config.appName) iOS \(Config.appVersion) (\(Config.buildNumber))").frame(maxWidth: .infinity).padding(.top, 8)
            }
        }
        .navigationTitle("Hesabım")
        .confirmationDialog("Çıkış yapılsın mı?", isPresented: $cikisSor, titleVisibility: .visible) {
            Button("Çıkış yap", role: .destructive) { Task { await session.cikis() } }
        }
        .confirmationDialog("Firma bağlantısı ve bu telefondaki tüm oturum bilgileri silinecek.", isPresented: $firmaSor, titleVisibility: .visible) {
            Button("Firmayı değiştir", role: .destructive) { Task { await session.cikis(); session.firmayiDegistir() } }
        }
        .onAppear { biyometrik = Store.biyometrikAcik && Biometric.anahtarVar }
    }
}
