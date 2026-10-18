import SwiftUI
import UIKit

/// Her sekmenin kendi gezinme yığını
final class NavYolu: ObservableObject {
    @Published var path = NavigationPath()
    func git(_ r: Route) { path.append(r) }
    func geri() { if !path.isEmpty { path.removeLast() } }
}

struct Yigin<Kok: View>: View {
    @StateObject private var nav = NavYolu()
    @ViewBuilder let kok: () -> Kok

    var body: some View {
        NavigationStack(path: $nav.path) {
            kok().navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .environmentObject(nav)
    }
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .ekran(let id): EkranView(id: id)
        case .form(let id, let kayit): FormView(formId: id, kayit: kayit)
        case .sohbet(let kanal, let ad): SohbetView(kanal: kanal, ad: ad)
        case .destek: DestekView()
        case .tani: TaniView()
        }
    }
}

/// Bildirimden ya da başka bir sekmeden açılan ekran (kendi yığınıyla, sayfa olarak)
struct SayfaKabi: View {
    let route: Route
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Yigin {
            RouteView(route: route)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}

// MARK: - Eylemler (tek dokunuşluk işlemler, gezinme, arama, WhatsApp)

@MainActor
final class EylemModel: ObservableObject {
    @Published var onayBekleyen: Eylem?
    @Published var calisiyor = false
    /// İşlem başarılı olunca (ör. silmeden sonra geri dönmek için)
    var bitti: ((Eylem) -> Void)?

    func yurut(_ e: Eylem, nav: NavYolu) {
        if let r = e.route { nav.git(r); return }
        if let u = e.disAdres { UIApplication.shared.open(u); return }
        guard e.istek != nil else { return }
        if e.onay != nil { onayBekleyen = e } else { Task { await istek(e) } }
    }

    func istek(_ e: Eylem) async {
        guard let id = e.istek, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let j = try await API.shared.cagir("eylem", sorgu: [("id", id)], govde: .form([]))
            Toast.shared.goster(j.str("msg") ?? "İşlem tamamlandı.")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            bitti?(e)
            NotificationCenter.default.post(name: .veriDegisti, object: nil)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Toast.shared.goster(error.localizedDescription, hata: true)
        }
    }
}

struct EylemKatmani: ViewModifier {
    @ObservedObject var model: EylemModel

    func body(content: Content) -> some View {
        content
            .environmentObject(model)
            .alert(model.onayBekleyen?.etiket ?? "Onay", isPresented: Binding(get: { model.onayBekleyen != nil }, set: { if !$0 { model.onayBekleyen = nil } }),
                   presenting: model.onayBekleyen) { e in
                Button(e.etiket.isEmpty ? "Onayla" : e.etiket, role: e.silme ? .destructive : nil) { Task { await model.istek(e) } }
                Button("Vazgeç", role: .cancel) {}
            } message: { e in
                Text(e.onay ?? "")
            }
            .overlay {
                if model.calisiyor {
                    ProgressView().controlSize(.large).padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
    }
}

extension View {
    func eylemKatmani(_ m: EylemModel) -> some View { modifier(EylemKatmani(model: m)) }
}

/// Yatay işlem düğmesi (detay ve panel ekranlarının üstünde)
struct EylemCipi: View {
    let e: Eylem
    @EnvironmentObject private var model: EylemModel
    @EnvironmentObject private var nav: NavYolu

    var body: some View {
        Button { model.yurut(e, nav: nav) } label: {
            Label(e.etiket, systemImage: e.ikon.isEmpty ? (e.istek != nil ? "bolt.fill" : "arrow.right") : Simge.ad(e.ikon))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(e.silme ? Tema.renk("red") : Tema.lacivert)
                .background((e.silme ? Tema.renk("red") : Tema.altin).opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Sağ üst köşedeki işlemler: ilk "ekle / düzenle" düğme olarak, diğerleri menüde
struct EylemAracCubugu: ToolbarContent {
    let eylemler: [Eylem]
    let model: EylemModel
    let nav: NavYolu

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let ilk = eylemler.first, eylemler.count == 1 {
                Button { model.yurut(ilk, nav: nav) } label: {
                    Image(systemName: ilk.ikon.isEmpty ? "plus" : Simge.ad(ilk.ikon))
                }
                .accessibilityLabel(ilk.etiket)
            } else if !eylemler.isEmpty {
                Menu {
                    ForEach(eylemler) { e in
                        Button(role: e.silme ? .destructive : nil) { model.yurut(e, nav: nav) } label: {
                            Label(e.etiket, systemImage: e.ikon.isEmpty ? "arrow.right" : Simge.ad(e.ikon))
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

/// Liste hücresi: dokununca ilgili ekran / form, sola kaydırınca işlemler
struct KalemHucre: View {
    let k: Kalem
    @EnvironmentObject private var model: EylemModel
    @EnvironmentObject private var nav: NavYolu

    var body: some View {
        Group {
            if let r = k.ac?.route {
                NavigationLink(value: r) { KalemSatiri(k: k) }
            } else if let a = k.ac, a.disAdres != nil || a.istek != nil {
                Button { model.yurut(a, nav: nav) } label: { KalemSatiri(k: k) }.buttonStyle(.plain)
            } else {
                KalemSatiri(k: k)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach(k.eylemler.reversed()) { e in
                Button(role: e.silme ? .destructive : nil) { model.yurut(e, nav: nav) } label: {
                    Label(e.etiket, systemImage: e.ikon.isEmpty ? (e.silme ? "trash" : "checkmark") : Simge.ad(e.ikon))
                }
                .tint(e.silme ? .red : Tema.altin)
            }
        }
        .contextMenu {
            ForEach(k.eylemler) { e in
                Button(role: e.silme ? .destructive : nil) { model.yurut(e, nav: nav) } label: {
                    Label(e.etiket, systemImage: e.ikon.isEmpty ? "bolt" : Simge.ad(e.ikon))
                }
            }
        }
    }
}
