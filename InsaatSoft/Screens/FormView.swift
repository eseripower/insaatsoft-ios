import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Sunucunun form alanı tanımı
struct FormAlani: Identifiable {
    let id: String
    let j: JSON
    var ad: String { id }
    var etiket: String { j["etiket"].string }
    var tip: String { j["tip"].string.isEmpty ? "metin" : j["tip"].string }
    var zorunlu: Bool { j["zorunlu"].bool }
    var ipucu: String? { j.str("ipucu") }
    var grup: String? { j.str("grup") }
    var kaynak: String { j["kaynak"].string }
    var ust: String? { j.str("ust") }
    var enCok: Int { j["en_cok"].int }
    var oneriler: [String] { j["oneriler"].stringArray }
    var kabul: String { j["kabul"].string }
    var secenekler: [Secenek] { j["secenekler"].array.map { Secenek(kod: $0["kod"].string, ad: $0["ad"].string) } }
    var altAlanlar: [FormAlani] { j["alt"].array.map { FormAlani(id: $0["ad"].string, j: $0) } }
    var varsayilan: String { j["varsayilan"].string }
    var cok: Bool { j["cok"].bool }                    // birden çok dosya
    var onizleme: String? { j.str("onizleme") }        // mevcut görsel
}

struct Secenek: Hashable { let kod: String; let ad: String }

struct SecilenDosya {
    let ad: String
    let mime: String
    let veri: Data
    let onizleme: UIImage?
}

@MainActor
final class FormModel: ObservableObject {
    @Published var tanim: JSON = .null
    @Published var alanlar: [FormAlani] = []
    @Published var metin: [String: String] = [:]
    @Published var liste: [String: [String]] = [:]
    @Published var satirlar: [String: [[String: String]]] = [:]
    @Published var dosya: [String: [SecilenDosya]] = [:]
    @Published var etiketAd: [String: String] = [:]       // bağlı alanların seçili kaydının adı
    @Published var eksik: Set<String> = []
    @Published var hata: String?
    @Published var gonderiliyor = false
    var gonderId = ""

    func yukle(_ formId: String, kayit: Int) async {
        do {
            var q: [(String, String)] = [("id", formId)]
            if kayit > 0 { q.append(("kayit", String(kayit))) }
            let j = try await API.shared.cagir("form", sorgu: q)
            tanim = j
            gonderId = j.str("id") ?? formId
            alanlar = j["alanlar"].array.enumerated().map { i, a in
                FormAlani(id: a["ad"].string.isEmpty ? "_alan\(i)" : a["ad"].string, j: a)
            }
            for a in alanlar {
                switch a.tip {
                case "coklu": liste[a.ad] = a.j["deger"].stringArray
                case "satirlar":
                    var r = a.j["deger"].array.map { s in Dictionary(uniqueKeysWithValues: a.altAlanlar.map { ($0.ad, s[$0.ad].string) }) }
                    if r.isEmpty { r = [bosSatir(a)] }
                    satirlar[a.ad] = r
                case "dosya", "bilgi": break
                default:
                    metin[a.ad] = a.j["deger"].string
                    if a.tip == "bagli" { etiketAd[a.ad] = a.j["deger_ad"].string }
                }
            }
            hata = nil
        } catch {
            hata = error.localizedDescription
        }
    }

    func bosSatir(_ a: FormAlani) -> [String: String] {
        Dictionary(uniqueKeysWithValues: a.altAlanlar.map { ($0.ad, $0.varsayilan) })
    }

    func deger(_ ad: String) -> Binding<String> {
        Binding(get: { self.metin[ad] ?? "" }, set: { yeni in
            let eski = self.metin[ad] ?? ""
            self.metin[ad] = yeni
            self.eksik.remove(ad)
            // il → ilçe → mahalle zinciri: üst alan değişince alt alan temizlenir
            if eski != yeni {
                for alt in self.alanlar where alt.ust == ad {
                    self.metin[alt.ad] = ""
                    self.etiketAd[alt.ad] = ""
                }
            }
        })
    }

    private func dolu(_ a: FormAlani) -> Bool {
        switch a.tip {
        case "bilgi": return true
        case "coklu": return !(liste[a.ad] ?? []).isEmpty
        case "dosya": return !(dosya[a.ad] ?? []).isEmpty
        case "onay": return (metin[a.ad] ?? "") == "1"
        case "satirlar":
            let ilk = a.altAlanlar.first?.ad ?? ""
            return (satirlar[a.ad] ?? []).contains { !($0[ilk] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        default: return !(metin[a.ad] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Kaydet: multipart/form-data, alan adları web panelindeki formla aynı (coklu → ad[], satırlar → altalan[])
    /// Başarılıysa sunucunun yanıtını döndürür (msg, sonuc, ac)
    func gonder(kayit: Int) async -> JSON? {
        eksik = Set(alanlar.filter { $0.zorunlu && !dolu($0) }.map(\.ad))
        if !eksik.isEmpty {
            let adlar = alanlar.filter { eksik.contains($0.ad) }.map(\.etiket).prefix(3).joined(separator: ", ")
            Toast.shared.goster("Zorunlu alanları doldurun: \(adlar)", hata: true)
            return nil
        }
        var m = Multipart()
        for a in alanlar where !a.ad.hasPrefix("_") {
            switch a.tip {
            case "bilgi": continue
            case "coklu":
                for v in liste[a.ad] ?? [] { m.add(a.ad + "[]", v) }
            case "satirlar":
                let ilk = a.altAlanlar.first?.ad ?? ""
                let dolular = (satirlar[a.ad] ?? []).filter { s in
                    if ilk.isEmpty { return true }
                    return !(s[ilk] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                }
                for s in dolular { for alt in a.altAlanlar { m.add(alt.ad + "[]", s[alt.ad] ?? "") } }
            case "dosya":
                for d in dosya[a.ad] ?? [] { m.addFile(a.ad, filename: d.ad, mime: d.mime, content: d.veri) }
            default:
                m.add(a.ad, metin[a.ad] ?? "")
            }
        }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            var q: [(String, String)] = [("id", gonderId)]
            if kayit > 0 { q.append(("kayit", String(kayit))) }
            let dosyaVar = dosya.values.contains { !$0.isEmpty }
            return try await API.shared.cagir("gonder", sorgu: q, govde: .multipart(m), zamanAsimi: dosyaVar ? 180 : 45)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Toast.shared.goster(error.localizedDescription, hata: true)
            return nil
        }
    }
}

struct FormView: View {
    let formId: String
    let kayit: Int
    @StateObject private var vm = FormModel()
    @Environment(\.dismiss) private var dismiss
    @State private var sonuc: SonucHedef?

    var body: some View {
        Group {
            if vm.tanim.isNull {
                if let h = vm.hata { HataView(mesaj: h) { Task { await vm.yukle(formId, kayit: kayit) } } } else { YukleniyorView() }
            } else {
                Form {
                    if let a = vm.tanim.str("alt_baslik") {
                        Section { Text(a).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    ForEach(gruplar) { g in
                        Section {
                            ForEach(g.alanlar) { a in AlanGirdisi(a: a, vm: vm) }
                        } header: {
                            if let b = g.baslik { Text(b) }
                        }
                    }
                    Section {
                        Button {
                            Task {
                                if let j = await vm.gonder(kayit: kayit) {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    Toast.shared.goster(j.str("msg") ?? "Kaydedildi.")
                                    NotificationCenter.default.post(name: .veriDegisti, object: nil)
                                    if let a = Eylem(j["ac"]), let u = a.disAdres { UIApplication.shared.open(u) }
                                    if j["sonuc"].isObject { sonuc = SonucHedef(j: j["sonuc"]) } else { dismiss() }
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if vm.gonderiliyor { ProgressView().tint(.white) } else { Text(vm.tanim.str("dugme") ?? "Kaydet").fontWeight(.semibold) }
                                Spacer()
                            }
                        }
                        .listRowBackground(Tema.altin)
                        .foregroundStyle(.white)
                        .disabled(vm.gonderiliyor)
                    } footer: {
                        if let n = vm.tanim.str("not") { Text(n) }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle(vm.tanim.str("baslik") ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .task { if vm.tanim.isNull { await vm.yukle(formId, kayit: kayit) } }
        .interactiveDismissDisabled(vm.gonderiliyor)
        .sheet(item: $sonuc, onDismiss: { dismiss() }) { SonucView(j: $0.j) }
    }

    /// Alanlar "grup" başlığı görülen yerden itibaren yeni bölüme ayrılır (web panelindeki gibi)
    private struct Grup: Identifiable { let id: Int; let baslik: String?; let alanlar: [FormAlani] }

    private var gruplar: [Grup] {
        var out: [Grup] = []
        var baslik: String? = nil
        var biriken: [FormAlani] = []
        for a in vm.alanlar {
            if let g = a.grup, g != baslik {
                if !biriken.isEmpty { out.append(Grup(id: out.count, baslik: baslik, alanlar: biriken)) }
                baslik = g
                biriken = []
            }
            biriken.append(a)
        }
        if !biriken.isEmpty { out.append(Grup(id: out.count, baslik: baslik, alanlar: biriken)) }
        return out
    }
}

// MARK: - Alan girdileri

struct AlanGirdisi: View {
    let a: FormAlani
    @ObservedObject var vm: FormModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            girdi
            if let i = a.ipucu, a.tip != "bilgi" { Text(i).font(.caption).foregroundStyle(.secondary) }
            if vm.eksik.contains(a.ad) { Text("Bu alan zorunlu.").font(.caption).foregroundStyle(.red) }
        }
    }

    private var etiket: String { a.etiket + (a.zorunlu ? " *" : "") }

    @ViewBuilder private var girdi: some View {
        switch a.tip {
        case "bilgi":
            Text(a.etiket).font(.subheadline).foregroundStyle(.secondary)
        case "uzun":
            VStack(alignment: .leading, spacing: 4) {
                Text(etiket).font(.caption).foregroundStyle(.secondary)
                TextField("", text: vm.deger(a.ad), axis: .vertical).lineLimit(3...10)
            }
        case "parola":
            SecureField(etiket, text: vm.deger(a.ad)).textContentType(.password)
        case "onay":
            Toggle(etiket, isOn: Binding(get: { (vm.metin[a.ad] ?? "") == "1" }, set: { vm.deger(a.ad).wrappedValue = $0 ? "1" : "" }))
                .tint(Tema.altin)
        case "secim":
            Picker(etiket, selection: vm.deger(a.ad)) {
                if !a.zorunlu || (vm.metin[a.ad] ?? "").isEmpty { Text("Seçin").tag("") }
                ForEach(a.secenekler, id: \.kod) { s in Text(s.ad).tag(s.kod) }
            }
        case "tarih":
            TarihGirdisi(etiket: etiket, deger: vm.deger(a.ad), saat: false)
        case "saat":
            TarihGirdisi(etiket: etiket, deger: vm.deger(a.ad), saat: true)
        case "bagli":
            let ustDeger = a.ust.map { vm.metin[$0] ?? "" }
            NavigationLink {
                SecenekView(baslik: a.etiket, kaynak: a.kaynak, ust: ustDeger ?? "", secili: vm.metin[a.ad] ?? "") { kod, ad in
                    vm.deger(a.ad).wrappedValue = kod
                    vm.etiketAd[a.ad] = ad
                }
            } label: {
                HStack {
                    Text(etiket)
                    Spacer()
                    Text(secimMetni(ustDeger)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .disabled(ustDeger == "")
        case "coklu":
            NavigationLink {
                CokluSecimView(baslik: a.etiket, secenekler: a.secenekler, secili: Binding(get: { vm.liste[a.ad] ?? [] }, set: { vm.liste[a.ad] = $0; vm.eksik.remove(a.ad) }))
            } label: {
                HStack {
                    Text(etiket)
                    Spacer()
                    let s = vm.liste[a.ad] ?? []
                    Text(s.isEmpty ? "Seçin" : (s.count <= 2 ? a.secenekler.filter { s.contains($0.kod) }.map(\.ad).joined(separator: ", ") : "\(s.count) seçili"))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
        case "dosya":
            DosyaGirdisi(a: a, etiket: etiket, secilen: Binding(get: { vm.dosya[a.ad] ?? [] }, set: { vm.dosya[a.ad] = $0; vm.eksik.remove(a.ad) }))
        case "satirlar":
            SatirlarGirdisi(a: a, vm: vm)
        default:
            MetinGirdisi(a: a, etiket: etiket, deger: vm.deger(a.ad))
        }
    }

    private func secimMetni(_ ustDeger: String?) -> String {
        if ustDeger == "" { return "Önce üst alanı seçin" }
        let k = vm.metin[a.ad] ?? ""
        if k.isEmpty { return "Seçin" }
        return (vm.etiketAd[a.ad] ?? "").isEmpty ? "#\(k)" : vm.etiketAd[a.ad]!
    }
}

struct MetinGirdisi: View {
    let a: FormAlani
    let etiket: String
    @Binding var deger: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if !deger.isEmpty { Text(etiket).font(.caption2).foregroundStyle(.secondary) }
                TextField(etiket, text: Binding(get: { deger }, set: { deger = a.enCok > 0 ? String($0.prefix(a.enCok)) : $0 }))
                    .keyboardType(klavye)
                    .textInputAutocapitalization(a.tip == "eposta" ? .never : .sentences)
                    .autocorrectionDisabled(["eposta", "tel", "sayi", "ondalik", "para"].contains(a.tip))
                    .textContentType(a.tip == "eposta" ? .emailAddress : (a.tip == "tel" ? .telephoneNumber : nil))
            }
            if a.tip == "para" { Text("₺").foregroundStyle(.secondary) }
            if !a.oneriler.isEmpty {
                Menu {
                    ForEach(a.oneriler, id: \.self) { o in Button(o) { deger = o } }
                } label: { Image(systemName: "text.badge.plus").foregroundStyle(Tema.altin) }
            }
        }
    }

    private var klavye: UIKeyboardType {
        switch a.tip {
        case "sayi": return .numberPad
        case "ondalik", "para": return .decimalPad
        case "tel": return .phonePad
        case "eposta": return .emailAddress
        default: return .default
        }
    }
}

/// "YYYY-MM-DD" / "HH:MM" metnine bağlı tarih-saat seçici; boş bırakılabilir
struct TarihGirdisi: View {
    let etiket: String
    @Binding var deger: String
    let saat: Bool

    private var bicim: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = saat ? "HH:mm" : "yyyy-MM-dd"
        return f
    }

    var body: some View {
        HStack {
            if deger.isEmpty {
                Text(etiket)
                Spacer()
                Button(saat ? "Saat seç" : "Tarih seç") { deger = bicim.string(from: Date()) }.buttonStyle(.bordered).tint(Tema.altin)
            } else {
                DatePicker(etiket, selection: Binding(get: { bicim.date(from: String(deger.prefix(saat ? 5 : 10))) ?? Date() }, set: { deger = bicim.string(from: $0) }),
                           displayedComponents: saat ? .hourAndMinute : .date)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                Button { deger = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Aranabilir seçim listesi (secenek?k=<kaynak>&q=&ust=)

struct SecenekView: View {
    let baslik: String
    let kaynak: String
    let ust: String
    let secili: String
    let sec: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ara = ""
    @State private var liste: [JSON] = []
    @State private var yukleniyor = true
    @State private var hata: String?

    var body: some View {
        List {
            if !secili.isEmpty {
                Button(role: .destructive) { sec("", ""); dismiss() } label: { Label("Seçimi kaldır", systemImage: "xmark.circle") }
            }
            if let h = hata { Text(h).foregroundStyle(.secondary) }
            ForEach(Array(liste.enumerated()), id: \.offset) { _, o in
                Button { sec(o["kod"].string, o["ad"].string); dismiss() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o["ad"].string).foregroundStyle(.primary)
                            if let alt = o.str("alt") { Text(alt).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if o["kod"].string == secili { Image(systemName: "checkmark").foregroundStyle(Tema.altin) }
                    }
                }
            }
            if !yukleniyor && liste.isEmpty && hata == nil { Text("Sonuç yok.").foregroundStyle(.secondary) }
        }
        .overlay { if yukleniyor && liste.isEmpty { ProgressView() } }
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $ara, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ara")
        .task(id: ara) {
            if !ara.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
            if Task.isCancelled { return }
            yukleniyor = true
            do {
                var q: [(String, String)] = [("k", kaynak), ("q", ara)]
                if !ust.isEmpty { q.append(("ust", ust)) }
                let j = try await API.shared.cagir("secenek", sorgu: q)
                liste = j["secenekler"].array
                hata = nil
            } catch {
                if !Task.isCancelled { hata = error.localizedDescription }
            }
            yukleniyor = false
        }
    }
}

struct CokluSecimView: View {
    let baslik: String
    let secenekler: [Secenek]
    @Binding var secili: [String]

    var body: some View {
        List {
            ForEach(secenekler, id: \.kod) { s in
                Button {
                    if let i = secili.firstIndex(of: s.kod) { secili.remove(at: i) } else { secili.append(s.kod) }
                } label: {
                    HStack {
                        Text(s.ad).foregroundStyle(.primary)
                        Spacer()
                        if secili.contains(s.kod) { Image(systemName: "checkmark").foregroundStyle(Tema.altin).fontWeight(.semibold) }
                    }
                }
            }
        }
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(secili.count == secenekler.count ? "Hiçbiri" : "Tümü") {
                    secili = secili.count == secenekler.count ? [] : secenekler.map(\.kod)
                }
            }
        }
    }
}

// MARK: - Kalem satırları (e-Fatura kalemleri vb.)

struct SatirlarGirdisi: View {
    let a: FormAlani
    @ObservedObject var vm: FormModel

    var body: some View {
        let satirlar = vm.satirlar[a.ad] ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text(a.etiket + (a.zorunlu ? " *" : "")).font(.subheadline.weight(.semibold))
            ForEach(satirlar.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(i + 1). satır").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if satirlar.count > 1 {
                            Button(role: .destructive) { vm.satirlar[a.ad]?.remove(at: i) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                    ForEach(a.altAlanlar) { alt in
                        let b = Binding<String>(get: { vm.satirlar[a.ad]?[safe: i]?[alt.ad] ?? "" },
                                                set: { if vm.satirlar[a.ad]?.indices.contains(i) == true { vm.satirlar[a.ad]![i][alt.ad] = $0; vm.eksik.remove(a.ad) } })
                        if alt.tip == "secim" {
                            Picker(alt.etiket, selection: b) { ForEach(alt.secenekler, id: \.kod) { Text($0.ad).tag($0.kod) } }
                        } else {
                            MetinGirdisi(a: alt, etiket: alt.etiket, deger: b)
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            Button { vm.satirlar[a.ad, default: []].append(vm.bosSatir(a)) } label: { Label("Satır ekle", systemImage: "plus.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(Tema.altin)
        }
        .padding(.vertical, 4)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Fotoğraf / belge

struct DosyaGirdisi: View {
    let a: FormAlani
    let etiket: String
    @Binding var secilen: [SecilenDosya]
    @State private var fotoSecim: [PhotosPickerItem] = []
    @State private var kamera = false
    @State private var dosyaSec = false

    /// Kabul edilen türler: "image/*" yalnızca görsel; "pdf" içeriyorsa görsel + PDF; boşsa her dosya
    private var yalnizGorsel: Bool { a.kabul.hasPrefix("image") && !a.kabul.contains("pdf") }
    private var dosyaTurleri: [UTType] {
        if yalnizGorsel { return [.image] }
        if a.kabul.contains("pdf") && !a.kabul.contains("*/*") { return [.pdf, .image] }
        return [.item]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(etiket)
            if let o = a.onizleme, secilen.isEmpty {
                HStack(spacing: 10) {
                    YetkiliResim(adres: o).frame(width: 56, height: 56).background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Mevcut görsel").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(secilen.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 10) {
                    if let r = s.onizleme {
                        Image(uiImage: r).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "doc.fill").font(.title).foregroundStyle(Tema.altin).frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading) {
                        Text(s.ad).font(.subheadline).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(s.veri.count), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) { if secilen.indices.contains(i) { secilen.remove(at: i) } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                }
            }
            HStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { kamera = true } label: { Label("Çek", systemImage: "camera.fill") }.buttonStyle(.bordered)
                }
                PhotosPicker(selection: $fotoSecim, maxSelectionCount: a.cok ? 20 : 1, matching: .images) { Label("Galeri", systemImage: "photo") }.buttonStyle(.bordered)
                if !yalnizGorsel {
                    Button { dosyaSec = true } label: { Label("Dosya", systemImage: "doc") }.buttonStyle(.bordered)
                }
            }
            .tint(Tema.altin)
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .onChange(of: fotoSecim) { yeni in
            guard !yeni.isEmpty else { return }
            Task {
                var eklenen: [SecilenDosya] = []
                for oge in yeni {
                    if let d = try? await oge.loadTransferable(type: Data.self), let r = UIImage(data: d), let j = DosyaGirdisi.jpeg(r) { eklenen.append(j) }
                }
                ekle(eklenen)
                fotoSecim = []
            }
        }
        .sheet(isPresented: $kamera) {
            KameraView { r in if let j = DosyaGirdisi.jpeg(r) { ekle([j]) } }.ignoresSafeArea()
        }
        .fileImporter(isPresented: $dosyaSec, allowedContentTypes: dosyaTurleri, allowsMultipleSelection: a.cok) { sonuc in
            guard case .success(let adresler) = sonuc else { return }
            var eklenen: [SecilenDosya] = []
            for u in adresler {
                let erisim = u.startAccessingSecurityScopedResource()
                defer { if erisim { u.stopAccessingSecurityScopedResource() } }
                guard let d = try? Data(contentsOf: u) else { Toast.shared.goster("Dosya okunamadı.", hata: true); continue }
                if d.count > 15 * 1024 * 1024 { Toast.shared.goster("Dosya en fazla 15 MB olabilir: \(u.lastPathComponent)", hata: true); continue }
                let uzanti = u.pathExtension.lowercased()
                let tur = UTType(filenameExtension: uzanti)
                if tur?.conforms(to: .image) == true, uzanti != "gif", uzanti != "svg", let r = UIImage(data: d), let j = DosyaGirdisi.jpeg(r) {
                    eklenen.append(j)
                } else {
                    let mime = uzanti == "pdf" ? "application/pdf" : (tur?.preferredMIMEType ?? "application/octet-stream")
                    eklenen.append(SecilenDosya(ad: DosyaGirdisi.guvenliAd(u.lastPathComponent), mime: mime, veri: d, onizleme: nil))
                }
            }
            ekle(eklenen)
        }
    }

    private func ekle(_ yeni: [SecilenDosya]) {
        guard !yeni.isEmpty else { return }
        if a.cok { secilen += yeni } else { secilen = [yeni[yeni.count - 1]] }
    }

    /// Fotoğraf en fazla 2560 px'e küçültülür ve JPEG'e çevrilir (yön düzeltilir, konum bilgisi taşınmaz)
    static func jpeg(_ r: UIImage) -> SecilenDosya? {
        let enFazla: CGFloat = 2560
        let o = min(1, enFazla / max(r.size.width, r.size.height))
        let boyut = CGSize(width: floor(r.size.width * o), height: floor(r.size.height * o))
        let bicim = UIGraphicsImageRendererFormat.default()
        bicim.scale = 1
        let yeni = UIGraphicsImageRenderer(size: boyut, format: bicim).image { _ in r.draw(in: CGRect(origin: .zero, size: boyut)) }
        guard let d = yeni.jpegData(compressionQuality: 0.82) else { return nil }
        let ad = "foto-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".jpg"
        return SecilenDosya(ad: ad, mime: "image/jpeg", veri: d, onizleme: yeni)
    }

    static func guvenliAd(_ s: String) -> String {
        let izinli = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let t = String(s.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR")).map { izinli.contains($0) ? $0 : "-" })
        return t.isEmpty ? "belge.pdf" : t
    }
}

struct KameraView: UIViewControllerRepresentable {
    let cekildi: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let ust: KameraView
        init(_ u: KameraView) { ust = u }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let r = info[.originalImage] as? UIImage { ust.cekildi(r) }
            ust.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { ust.dismiss() }
    }
}
