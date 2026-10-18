import SwiftUI
import UIKit
import Charts

/// Sunucu tanımlı ekran: GET ekran?id=<kimlik>&q=&sayfa=&f_<süzgeç>=
/// Yanıtın "tur" alanına göre liste | detay | panel | tablo olarak çizilir.
@MainActor
final class EkranModel: ObservableObject {
    @Published var veri: JSON = .null
    @Published var hata: String?
    @Published var yukleniyor = false
    @Published var kalemler: [Kalem] = []
    @Published var sayfa = 1
    @Published var sayfaSayisi = 1
    @Published var dahaYukleniyor = false
    @Published var ara = ""
    @Published var suzgec: [String: String] = [:]
    @Published var suzgecAd: [String: String] = [:]     // bağlı süzgeçlerde seçili kaydın adı
    @Published var secimModu = false                    // toplu işlem seçimi
    @Published var secili: Set<String> = []
    private var istekNo = 0

    var tur: String { veri["tur"].string }
    var toplu: [Eylem] { Eylem.liste(veri["toplu"]) }

    private func sorgu(_ id: String, sayfa: Int) -> [(String, String)] {
        var q: [(String, String)] = [("id", id)]
        if sayfa > 1 { q.append(("sayfa", String(sayfa))) }
        if !ara.trimmingCharacters(in: .whitespaces).isEmpty { q.append(("q", ara.trimmingCharacters(in: .whitespaces))) }
        for (k, v) in suzgec.sorted(by: { $0.key < $1.key }) { q.append(("f_" + k, v)) }
        return q
    }

    func yukle(_ id: String, sessiz: Bool = false, hataGoster: Bool = true) async {
        istekNo += 1
        let no = istekNo
        if !sessiz || veri.isNull { yukleniyor = veri.isNull }
        do {
            let j = try await API.shared.cagir("ekran", sorgu: sorgu(id, sayfa: 1))
            guard no == istekNo else { return }
            veri = j
            hata = nil
            kalemler = Kalem.liste(j["kayitlar"])
            sayfa = max(1, j["sayfa"].int)
            sayfaSayisi = max(1, j["sayfa_sayisi"].int)
            let mevcut = Set(kalemler.map(\.sunucuId))
            secili = secili.intersection(mevcut)
            if j["toplu"].array.isEmpty { secimModu = false }
        } catch {
            guard no == istekNo else { return }
            if veri.isNull { hata = error.localizedDescription } else if hataGoster, (error as? APIError)?.kod != "iptal" { Toast.shared.goster(error.localizedDescription, hata: true) }
        }
        yukleniyor = false
    }

    func devam(_ id: String) async {
        guard sayfa < sayfaSayisi, !dahaYukleniyor else { return }
        dahaYukleniyor = true
        defer { dahaYukleniyor = false }
        let no = istekNo
        guard let j = try? await API.shared.cagir("ekran", sorgu: sorgu(id, sayfa: sayfa + 1)), no == istekNo else { return }
        let baslangic = kalemler.count
        kalemler += j["kayitlar"].array.enumerated().map { Kalem($0.element, sira: baslangic + $0.offset) }
        sayfa = max(sayfa + 1, j["sayfa"].int)
        sayfaSayisi = max(1, j["sayfa_sayisi"].int)
    }

    func suzgecDegisti(_ id: String) {
        Task { await yukle(id, sessiz: true) }
    }
}

struct EkranView: View {
    let id: String
    var kok = false
    @StateObject private var vm = EkranModel()
    @StateObject private var eylem = EylemModel()
    @EnvironmentObject private var nav: NavYolu
    @Environment(\.dismiss) private var dismiss
    @State private var aramaGorevi: Task<Void, Never>?

    var body: some View {
        Group {
            if vm.veri.isNull {
                if let h = vm.hata { HataView(mesaj: h) { Task { await vm.yukle(id) } } } else { YukleniyorView() }
            } else {
                switch vm.tur {
                case "liste": ListeGovde(vm: vm, id: id)
                case "panel": PanelGovde(j: vm.veri, vm: vm, ekranId: id)
                case "tablo": TabloGovde(j: vm.veri, vm: vm, ekranId: id)
                default: DetayGovde(j: vm.veri, vm: vm, ekranId: id)
                }
            }
        }
        .navigationTitle(vm.veri.str("baslik") ?? "")
        .navigationBarTitleDisplayMode(kok ? .large : .inline)
        .toolbar {
            if vm.secimModu {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { vm.secimModu = false; vm.secili = [] }
                }
                TopluAracCubugu(vm: vm, model: eylem, nav: nav)
            } else {
                EylemAracCubugu(eylemler: vm.tur == "detay" || vm.tur == "panel" ? [] : Eylem.liste(vm.veri["eylemler"]), model: eylem, nav: nav)
                if vm.tur == "liste", !vm.toplu.isEmpty, !vm.kalemler.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Seç") { vm.secili = []; vm.secimModu = true }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(vm.secimModu ? .active : .inactive))
        .eylemKatmani(eylem)
        .task { if vm.veri.isNull { await vm.yukle(id) } }
        .onReceive(NotificationCenter.default.publisher(for: .veriDegisti)) { _ in Task { await vm.yukle(id, sessiz: true, hataGoster: false) } }
        .onAppear {
            let m = vm
            eylem.bitti = { [weak m] e in
                if e.geri { dismiss() }
                if m?.secimModu == true { m?.secimModu = false; m?.secili = [] }
            }
        }
        .modifier(AramaDestegi(etkin: vm.tur == "liste" && vm.veri["ara"].bool, ipucu: vm.veri.str("ara_ipucu") ?? "Ara", metin: $vm.ara) {
            aramaGorevi?.cancel()
            aramaGorevi = Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if !Task.isCancelled { await vm.yukle(id, sessiz: true) }
            }
        })
    }
}

/// Toplu işlem çubuğu: tümünü seç, seçili sayısı ve işlemler (alt çubukta)
private struct TopluAracCubugu: ToolbarContent {
    let vm: EkranModel   // EkranView gözlemler; değişince çubuk yeniden kurulur
    let model: EylemModel
    let nav: NavYolu

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            let tumu = vm.kalemler.map(\.sunucuId).filter { !$0.isEmpty }
            Button(vm.secili.count == tumu.count && !tumu.isEmpty ? "Hiçbiri" : "Tümünü seç") {
                vm.secili = vm.secili.count == tumu.count ? [] : Set(tumu)
            }
            Spacer()
            Text(vm.secili.isEmpty ? "Kayıt seçin" : "\(vm.secili.count) seçili").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(vm.toplu) { e in
                    Button(role: e.silme ? .destructive : nil) {
                        model.yurut(e, nav: nav, idler: vm.secili.filter { !$0.isEmpty }.sorted())
                    } label: {
                        Label(e.etiket, systemImage: e.ikon.isEmpty ? (e.silme ? "trash" : "checkmark.circle") : Simge.ad(e.ikon))
                    }
                }
            } label: {
                Text("İşlemler").fontWeight(.semibold)
            }
            .disabled(vm.secili.isEmpty)
        }
    }
}

/// Liste ekranlarında arama çubuğu (yalnızca sunucu "ara: true" derse)
private struct AramaDestegi: ViewModifier {
    let etkin: Bool
    let ipucu: String
    @Binding var metin: String
    let degisti: () -> Void

    func body(content: Content) -> some View {
        if etkin {
            content
                .searchable(text: $metin, placement: .navigationBarDrawer(displayMode: .always), prompt: ipucu)
                .onChange(of: metin) { _ in degisti() }
        } else {
            content
        }
    }
}

// MARK: - Liste

private struct ListeGovde: View {
    @ObservedObject var vm: EkranModel
    let id: String

    var body: some View {
        let j = vm.veri
        List(selection: $vm.secili) {
            if let a = j.str("alt_baslik") {
                Text(a).font(.subheadline).foregroundStyle(.secondary).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            if let o = j.str("ozet") {
                Text(o).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.altin).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            ForEach(Array(j["uyarilar"].array.enumerated()), id: \.offset) { _, u in
                Uyari(metin: u["metin"].string, renk: u["renk"].string).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            let kartlar = j["kartlar"].array
            if !kartlar.isEmpty {
                KartSeridi(kartlar: kartlar).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            SuzgecSeridi(vm: vm, id: id)
            Section {
                if vm.kalemler.isEmpty {
                    BosView(mesaj: j.str("bos") ?? "Kayıt yok.").listRowBackground(Color.clear)
                } else {
                    ForEach(vm.kalemler) { k in KalemHucre(k: k).tag(k.sunucuId) }
                    if vm.sayfa < vm.sayfaSayisi {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .onAppear { Task { await vm.devam(id) } }
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                if j["toplam"].int > 0 { Text("\(j["toplam"].int) kayıt") }
            } footer: {
                if let n = j.str("not") { Text(n) }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.yukle(id, sessiz: true) }
    }
}

struct KartSeridi: View {
    let kartlar: [JSON]
    @EnvironmentObject private var nav: NavYolu
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(kartlar.enumerated()), id: \.offset) { _, k in
                    Button { if let r = Eylem(k["ac"])?.route { nav.git(r) } } label: { OzetKarti(j: k).frame(width: 150) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
        }
    }
}

/// Süzgeç çipleri (seçim, tarih, bağlı kayıt). Liste, detay ve panel ekranlarında listenin bir satırı olarak.
struct SuzgecSeridi: View {
    @ObservedObject var vm: EkranModel
    let id: String

    var body: some View {
        let suz = vm.veri["suzgecler"].array
        if !suz.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(suz.enumerated()), id: \.offset) { _, s in
                        let ad = s["ad"].string
                        SuzgecCipi(s: s, deger: vm.suzgec[ad] ?? s["deger"].string, degerAd: vm.suzgecAd[ad] ?? s["deger_ad"].string) { yeni, yeniAd in
                            vm.suzgec[ad] = yeni
                            vm.suzgecAd[ad] = yeniAd
                            vm.suzgecDegisti(id)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }
}

private struct SuzgecCipi: View {
    let s: JSON
    let deger: String
    let degerAd: String
    let sec: (String, String) -> Void
    @State private var tarihAcik = false
    @State private var bagliAcik = false

    private var bos: String { s.str("bos") ?? s["etiket"].string }

    var body: some View {
        switch s["tip"].string {
        case "tarih":
            Button { tarihAcik = true } label: { cip(deger.isEmpty ? s["etiket"].string : s["etiket"].string + ": " + TarihSuzgecSayfasi.goster(deger)) }
                .buttonStyle(.plain)
                .sheet(isPresented: $tarihAcik) {
                    TarihSuzgecSayfasi(baslik: s["etiket"].string, deger: deger) { sec($0, "") }
                        .presentationDetents([.medium, .large])
                }
        case "bagli":
            Button { bagliAcik = true } label: { cip(deger.isEmpty ? bos : (degerAd.isEmpty ? "#" + deger : degerAd)) }
                .buttonStyle(.plain)
                .sheet(isPresented: $bagliAcik) {
                    NavigationStack {
                        SecenekView(baslik: s["etiket"].string, kaynak: s["kaynak"].string, ust: s["ust"].string, secili: deger) { kod, ad in sec(kod, ad) }
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { bagliAcik = false } } }
                    }
                }
        default:
            let secenekler = s["secenekler"].array
            let secili = secenekler.first { $0["kod"].string == deger }
            Menu {
                Button { sec("", "") } label: { if deger.isEmpty { Label(s.str("bos") ?? "Tümü", systemImage: "checkmark") } else { Text(s.str("bos") ?? "Tümü") } }
                ForEach(Array(secenekler.enumerated()), id: \.offset) { _, o in
                    Button { sec(o["kod"].string, o["ad"].string) } label: {
                        if o["kod"].string == deger { Label(o["ad"].string, systemImage: "checkmark") } else { Text(o["ad"].string) }
                    }
                }
            } label: {
                cip(secili?["ad"].string ?? bos)
            }
        }
    }

    private func cip(_ metin: String) -> some View {
        HStack(spacing: 4) {
            Text(metin).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(deger.isEmpty ? Color.primary : Color.white)
        .background(deger.isEmpty ? Color(.secondarySystemGroupedBackground) : Tema.altin, in: Capsule())
    }
}

/// Tarih süzgeci: takvimden gün seçimi, temizle
private struct TarihSuzgecSayfasi: View {
    let baslik: String
    let deger: String
    let sec: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tarih = Date()

    static let bicim: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func goster(_ s: String) -> String {
        guard let d = bicim.date(from: String(s.prefix(10))) else { return s }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(baslik, selection: $tarih, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                if !deger.isEmpty {
                    Button("Süzgeci kaldır", role: .destructive) { sec(""); dismiss() }
                }
            }
            .navigationTitle(baslik)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Uygula") { sec(TarihSuzgecSayfasi.bicim.string(from: tarih)); dismiss() }.fontWeight(.semibold) }
            }
        }
        .onAppear { if let d = TarihSuzgecSayfasi.bicim.date(from: String(deger.prefix(10))) { tarih = d } }
    }
}

// MARK: - Detay

struct DetayGovde: View {
    let j: JSON
    var vm: EkranModel? = nil
    var ekranId = ""
    @EnvironmentObject private var nav: NavYolu
    @State private var buyukResim: GaleriOgesi?

    var body: some View {
        List {
            if let a = j.str("alt_baslik") {
                Text(a).font(.subheadline).foregroundStyle(.secondary).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            ForEach(Array(j["uyarilar"].array.enumerated()), id: \.offset) { _, u in
                Uyari(metin: u["metin"].string, renk: u["renk"].string).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            let eylemler = Eylem.liste(j["eylemler"])
            if !eylemler.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(eylemler) { EylemCipi(e: $0) } }.padding(.horizontal, 16)
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
            if let vm { SuzgecSeridi(vm: vm, id: ekranId) }
            BolumListesi(bolumler: j["bolumler"].array, buyukResim: $buyukResim)
        }
        .listStyle(.insetGrouped)
        .refreshable { if let vm { await vm.yukle(ekranId, sessiz: true) } }
        .fullScreenCover(item: $buyukResim) { GaleriGorunumu(oge: $0) }
    }
}

struct GaleriOgesi: Identifiable { let id = UUID(); let etiket: String; let buyuk: String; let kucuk: String }

/// Detay ve panel ekranlarının bölümleri: alanlar | ogeler | galeri
struct BolumListesi: View {
    let bolumler: [JSON]
    @Binding var buyukResim: GaleriOgesi?

    var body: some View {
        ForEach(Array(bolumler.enumerated()), id: \.offset) { _, b in
            Section {
                let alanlar = b["alanlar"].array
                let ogeler = Kalem.liste(b["ogeler"])
                let galeri = b["galeri"].array.map { GaleriOgesi(etiket: $0["etiket"].string, buyuk: $0["buyuk"].string, kucuk: $0["kucuk"].string) }
                let bEylem = Eylem.liste(b["eylemler"])
                let tablo = b["tablo"]
                ForEach(Array(alanlar.enumerated()), id: \.offset) { _, a in AlanSatiri(a: a) }
                ForEach(ogeler) { KalemHucre(k: $0) }
                if tablo.isObject {
                    TabloIzgara(sutunlar: tablo["sutunlar"].stringArray, satirlar: tablo["satirlar"].array.map { $0.array.map { $0.string } })
                        .padding(.vertical, 4)
                }
                if !bEylem.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(bEylem) { EylemCipi(e: $0) } }
                    }
                    .padding(.vertical, 2)
                }
                if !galeri.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(galeri) { g in
                            Button { buyukResim = g } label: {
                                YetkiliResim(adres: g.kucuk).frame(height: 96).frame(maxWidth: .infinity).clipped()
                                    .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                if alanlar.isEmpty, ogeler.isEmpty, galeri.isEmpty, !tablo.isObject, let bos = b.str("bos") {
                    Text(bos).foregroundStyle(.secondary)
                }
                if let r = Eylem(b["tumu"])?.route {
                    NavigationLink(value: r) { Text("Tümünü gör").foregroundStyle(Tema.altin) }
                }
            } header: {
                if let t = b.str("baslik") { Text(t) }
            } footer: {
                if let n = b.str("not") { Text(n) }
            }
        }
    }
}

struct AlanSatiri: View {
    let a: JSON
    var body: some View {
        let etiket = a["etiket"].string
        let deger = a["deger"].string
        let renk = a["renk"].string
        let uzun = deger.count > 26 || deger.contains("\n")
        let icerik = Group {
            if uzun {
                VStack(alignment: .leading, spacing: 3) {
                    Text(etiket).font(.caption).foregroundStyle(.secondary)
                    Text(deger.isEmpty ? "—" : deger).foregroundStyle(renk.isEmpty || renk == "slate" ? Color.primary : Tema.renk(renk)).textSelection(.enabled)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(etiket).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    if !renk.isEmpty, renk != "slate", a["tel"].isNull, a["ac"].isNull {
                        Rozet(metin: deger, renk: renk)
                    } else {
                        Text(deger.isEmpty ? "—" : deger).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                }
            }
        }
        if let r = Eylem(a["ac"])?.route {
            NavigationLink(value: r) { icerik }
        } else if let t = a.str("tel"), let u = URL(string: "tel:" + t.filter { $0.isNumber || $0 == "+" }) {
            HStack {
                icerik
                Link(destination: u) { Image(systemName: "phone.fill").foregroundStyle(Tema.altin) }.buttonStyle(.borderless)
                if let w = Eylem.whatsapp(t) { Link(destination: w) { Image(systemName: "message.fill").foregroundStyle(Tema.renk("green")) }.buttonStyle(.borderless) }
            }
        } else {
            icerik
        }
    }
}

struct GaleriGorunumu: View {
    let oge: GaleriOgesi
    @Environment(\.dismiss) private var dismiss
    @State private var olcek: CGFloat = 1
    @State private var sonOlcek: CGFloat = 1

    var body: some View {
        NavigationStack {
            YetkiliResim(adres: oge.buyuk, dolgu: .fit)
                .scaleEffect(olcek)
                .gesture(MagnificationGesture()
                    .onChanged { olcek = max(1, min(5, sonOlcek * $0)) }
                    .onEnded { _ in sonOlcek = olcek })
                .onTapGesture(count: 2) { withAnimation { olcek = olcek > 1 ? 1 : 2.5; sonOlcek = olcek } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .navigationTitle(oge.etiket)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}

// MARK: - Panel (genel bakış)

struct PanelGovde: View {
    let j: JSON
    var vm: EkranModel? = nil
    var ekranId = ""
    @EnvironmentObject private var nav: NavYolu
    @State private var buyukResim: GaleriOgesi?

    var body: some View {
        List {
            if let a = j.str("alt_baslik") {
                Text(a).font(.subheadline).foregroundStyle(.secondary).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            ForEach(Array(j["uyarilar"].array.enumerated()), id: \.offset) { _, u in
                Uyari(metin: u["metin"].string, renk: u["renk"].string).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            let kartlar = j["kartlar"].array
            if !kartlar.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(kartlar.enumerated()), id: \.offset) { _, k in
                        Button { if let r = Eylem(k["ac"])?.route { nav.git(r) } } label: { OzetKarti(j: k) }.buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            let eylemler = Eylem.liste(j["eylemler"])
            if !eylemler.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(eylemler) { EylemCipi(e: $0) } }.padding(.horizontal, 16)
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if let vm { SuzgecSeridi(vm: vm, id: ekranId) }
            ForEach(Array(j["grafikler"].array.enumerated()), id: \.offset) { _, g in
                Section(g["baslik"].string) { Grafik(g: g).padding(.vertical, 6) }
            }
            BolumListesi(bolumler: j["bolumler"].array, buyukResim: $buyukResim)
        }
        .listStyle(.insetGrouped)
        .refreshable { if let vm { await vm.yukle(ekranId, sessiz: true) } }
        .fullScreenCover(item: $buyukResim) { GaleriGorunumu(oge: $0) }
    }
}

// MARK: - Grafik

struct Grafik: View {
    let g: JSON

    struct Nokta: Identifiable { let id: Int; let etiket: String; let deger: Double; let renk: String }

    var body: some View {
        let veri = g["veriler"].array.enumerated().map { Nokta(id: $0.offset, etiket: $0.element["etiket"].string, deger: $0.element["deger"].double, renk: $0.element["renk"].string) }
        if g["tur"].string == "yatay" {
            Chart(veri) { n in
                BarMark(x: .value("Değer", n.deger), y: .value("Kalem", n.etiket))
                    .foregroundStyle(Tema.renk(n.renk.isEmpty ? "#d69a42" : n.renk))
                    .annotation(position: .trailing) { Text(Grafik.bicim(n.deger)).font(.caption2).foregroundStyle(.secondary) }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(max(1, veri.count)) * 34 + 10)
        } else {
            Chart(veri) { n in
                BarMark(x: .value("Kalem", n.etiket), y: .value("Değer", n.deger))
                    .foregroundStyle(Tema.renk(n.renk.isEmpty ? "#d69a42" : n.renk))
                    .cornerRadius(3)
            }
            .frame(height: 200)
        }
    }

    static func bicim(_ d: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: d)) ?? "\(d)"
    }
}

// MARK: - Tablo (raporlar)

struct TabloGovde: View {
    let j: JSON
    var vm: EkranModel? = nil
    var ekranId = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let a = j.str("alt_baslik") { Text(a).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4) }
                if let vm, !j["suzgecler"].array.isEmpty { SuzgecSeridi(vm: vm, id: ekranId).padding(.horizontal, -16) }
                ForEach(Array(j["tablolar"].array.enumerated()), id: \.offset) { _, t in
                    VStack(alignment: .leading, spacing: 12) {
                        if let b = t.str("baslik") { Text(b).font(.headline) }
                        if t["grafik"].isObject { Grafik(g: t["grafik"]) }
                        TabloIzgara(sutunlar: t["sutunlar"].stringArray, satirlar: t["satirlar"].array.map { $0.array.map { $0.string } })
                    }
                    .kart()
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { if let vm { await vm.yukle(ekranId, sessiz: true) } }
    }
}

struct TabloIzgara: View {
    let sutunlar: [String]
    let satirlar: [[String]]
    var body: some View {
        if satirlar.isEmpty {
            Text("Bu raporda gösterilecek veri yok.").foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Array(sutunlar.enumerated()), id: \.offset) { i, s in
                            Text(s).font(.caption.weight(.semibold)).foregroundStyle(.secondary).gridColumnAlignment(i == 0 ? .leading : .trailing)
                        }
                    }
                    Divider()
                    ForEach(Array(satirlar.enumerated()), id: \.offset) { _, r in
                        GridRow {
                            ForEach(Array(r.enumerated()), id: \.offset) { i, h in
                                Text(h).font(.subheadline).monospacedDigit().lineLimit(2).frame(maxWidth: 220, alignment: i == 0 ? .leading : .trailing)
                            }
                        }
                        Divider()
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}
