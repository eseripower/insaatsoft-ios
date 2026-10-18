import SwiftUI
import UIKit

/// Web panelindeki menünün aynısı (kullanıcının yetkili olduğu bölümler): GET menu
struct MenuView: View {
    @EnvironmentObject private var session: Session
    @State private var ara = ""

    private struct Oge: Identifiable { let id: String; let ad: String; let ikon: String; let altlar: [JSON] }
    private struct Bolum: Identifiable { let id: String; let baslik: String; let ogeler: [Oge] }

    private var bolumler: [Bolum] {
        session.menu["bolumler"].array.enumerated().map { i, b in
            Bolum(id: "\(i)", baslik: b["baslik"].string, ogeler: b["ogeler"].array.enumerated().map { k, o in
                Oge(id: "\(i)-\(k)", ad: o["ad"].string, ikon: o["ikon"].string, altlar: o["alt"].array)
            })
        }
    }

    var body: some View {
        List {
            if ara.isEmpty {
                ForEach(bolumler) { b in
                    Section(b.baslik) {
                        ForEach(b.ogeler) { o in
                            if o.altlar.count == 1, let r = MenuView.hedef(o.altlar[0]) {
                                NavigationLink(value: r) { Label { Text(o.ad) } icon: { SimgeKutusu(ikon: o.ikon) } }
                            } else {
                                NavigationLink { AltMenu(baslik: o.ad, altlar: o.altlar) } label: {
                                    Label { Text(o.ad) } icon: { SimgeKutusu(ikon: o.ikon) }
                                }
                            }
                        }
                    }
                }
            } else {
                // Tüm alt bölümlerde arama
                let q = ara.lowercased(with: Locale(identifier: "tr_TR"))
                ForEach(bolumler) { b in
                    ForEach(b.ogeler) { o in
                        ForEach(Array(o.altlar.enumerated()), id: \.offset) { _, a in
                            let ad = a["ad"].string
                            if (ad + " " + o.ad).lowercased(with: Locale(identifier: "tr_TR")).contains(q), let r = MenuView.hedef(a) {
                                NavigationLink(value: r) {
                                    Label { VStack(alignment: .leading) { Text(ad); Text(o.ad).font(.caption).foregroundStyle(.secondary) } } icon: { SimgeKutusu(ikon: o.ikon) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Menü")
        .searchable(text: $ara, prompt: "Bölüm ara")
        .refreshable { await session.menuYukle() }
        .overlay { if session.menu.isNull { YukleniyorView().task { await session.menuYukle() } } }
    }

    static func hedef(_ a: JSON) -> Route? {
        if let f = a.str("form") { return .form(f, kayit: a["kayit"].int) }
        if let e = a.str("ekran") { return .ekran(e) }
        return nil
    }
}

private struct AltMenu: View {
    let baslik: String
    let altlar: [JSON]
    var body: some View {
        List {
            ForEach(Array(altlar.enumerated()), id: \.offset) { _, a in
                if let r = MenuView.hedef(a) {
                    NavigationLink(value: r) {
                        Label(a["ad"].string, systemImage: a.str("form") != nil ? "plus.circle" : "list.bullet")
                    }
                }
            }
        }
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
    }
}
