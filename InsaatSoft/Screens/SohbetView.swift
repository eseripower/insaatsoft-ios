import SwiftUI
import UIKit

/// Ekip sohbeti kanalları: GET sohbet_kanallar
struct SohbetListeView: View {
    @State private var kanallar: [JSON] = []
    @State private var hata: String?
    @State private var yuklendi = false

    var body: some View {
        List {
            if let h = hata, kanallar.isEmpty { Text(h).foregroundStyle(.secondary) }
            ForEach(Array(kanallar.enumerated()), id: \.offset) { _, k in
                NavigationLink(value: Route.sohbet(kanal: k["kanal"].string, ad: k["ad"].string)) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(k["grup"].bool ? Tema.altin.gradient : Tema.celik.gradient).frame(width: 42, height: 42)
                            if k["grup"].bool { Image(systemName: "person.3.fill").font(.footnote).foregroundStyle(.white) }
                            else { Text(String(k["ad"].string.prefix(1))).font(.headline).foregroundStyle(.white) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k["ad"].string).font(.body.weight(.semibold))
                            Text(k["son"]["metin"].string.isEmpty ? k["alt"].string : k["son"]["metin"].string)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if k["okunmamis"].int > 0 {
                            Text("\(k["okunmamis"].int)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Tema.altin, in: Capsule())
                        }
                    }
                }
            }
            if yuklendi && kanallar.isEmpty && hata == nil { BosView(mesaj: "Sohbet yok.") }
        }
        .navigationTitle("Ekip sohbeti")
        .refreshable { await yukle() }
        .task { await yukle() }
        .overlay { if !yuklendi { ProgressView() } }
    }

    private func yukle() async {
        do {
            kanallar = try await API.shared.cagir("sohbet_kanallar")["kanallar"].array
            hata = nil
        } catch { hata = error.localizedDescription }
        yuklendi = true
    }
}

/// Mesaj balonları (ekip sohbeti ve canlı destek ortak)
struct MesajBalonu: View {
    let ben: Bool
    let gonderen: String
    let metin: String
    let saat: String
    var silindi = false

    var body: some View {
        HStack {
            if ben { Spacer(minLength: 50) }
            VStack(alignment: ben ? .trailing : .leading, spacing: 3) {
                if !ben, !gonderen.isEmpty { Text(gonderen).font(.caption2.weight(.semibold)).foregroundStyle(Tema.altin) }
                Text(silindi ? "Mesaj silindi" : metin)
                    .italic(silindi)
                    .foregroundStyle(ben ? Color.white : Color.primary)
                    .textSelection(.enabled)
                Text(saat).font(.caption2).foregroundStyle(ben ? Color.white.opacity(0.7) : Color.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(ben ? Tema.lacivert : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !ben { Spacer(minLength: 50) }
        }
    }
}

/// Mesaj yazma çubuğu
struct MesajCubugu: View {
    @Binding var metin: String
    let gonderiliyor: Bool
    let gonder: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Mesaj yazın", text: $metin, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Button(action: gonder) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(Tema.altin)
            }
            .disabled(metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gonderiliyor)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }
}

/// Ekip sohbeti: GET sohbet?kanal=&son= (4 sn'de bir), POST sohbet {kanal, mesaj}
struct SohbetView: View {
    let kanal: String
    let ad: String
    @State private var mesajlar: [JSON] = []
    @State private var yazi = ""
    @State private var gonderiliyor = false
    @State private var hata: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { kaydir in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if let h = hata, mesajlar.isEmpty { Text(h).foregroundStyle(.secondary).padding() }
                        ForEach(Array(mesajlar.enumerated()), id: \.offset) { i, m in
                            if i == 0 || mesajlar[i - 1]["gun"].string != m["gun"].string, let g = m.str("gun") {
                                Text(SohbetView.gunMetni(g)).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 6)
                            }
                            MesajBalonu(ben: m["ben"].bool, gonderen: m["gonderen"].string, metin: m["mesaj"].string, saat: m["saat"].string, silindi: m["silindi"].bool)
                                .id(m["id"].int)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: mesajlar.count) { _ in
                    if let s = mesajlar.last { withAnimation { kaydir.scrollTo(s["id"].int, anchor: .bottom) } }
                }
            }
            MesajCubugu(metin: $yazi, gonderiliyor: gonderiliyor) { Task { await gonder() } }
        }
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await yukle()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await yukle()
            }
        }
    }

    private func yukle() async {
        let son = mesajlar.last?["id"].int ?? 0
        do {
            let j = try await API.shared.cagir("sohbet", sorgu: [("kanal", kanal)] + (son > 0 ? [("son", String(son))] : []))
            let yeni = j["mesajlar"].array
            if son == 0 { mesajlar = yeni } else {
                let var_ = Set(mesajlar.map { $0["id"].int })
                mesajlar += yeni.filter { !var_.contains($0["id"].int) }
            }
            hata = nil
        } catch { if mesajlar.isEmpty { hata = error.localizedDescription } }
    }

    private func gonder() async {
        let m = yazi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            try await API.shared.cagir("sohbet", govde: .form([("kanal", kanal), ("mesaj", m)]))
            yazi = ""
            await yukle()
        } catch { Toast.shared.goster(error.localizedDescription, hata: true) }
    }

    static func gunMetni(_ g: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: g) else { return g }
        if Calendar.current.isDateInToday(d) { return "Bugün" }
        if Calendar.current.isDateInYesterday(d) { return "Dün" }
        let t = DateFormatter()
        t.locale = Locale(identifier: "tr_TR")
        t.dateFormat = "d MMMM yyyy, EEEE"
        return t.string(from: d)
    }
}

/// KavisCloud canlı destek: GET destek?son= (3 sn'de bir), POST destek {mesaj}
struct DestekView: View {
    @State private var mesajlar: [JSON] = []
    @State private var yazi = ""
    @State private var gonderiliyor = false
    @State private var durum: JSON = .null
    @State private var hata: String?

    var body: some View {
        VStack(spacing: 0) {
            if let d = durumMetni {
                Text(d).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(8).background(Color(.secondarySystemBackground))
            }
            ScrollViewReader { kaydir in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if mesajlar.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "headphones").font(.largeTitle).foregroundStyle(Tema.altin)
                                Text(hata ?? "Destek ekibimize sorunuzu yazın; size buradan yanıt verilir.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                            }
                            .padding(.top, 60).padding(.horizontal, 30)
                        }
                        ForEach(Array(mesajlar.enumerated()), id: \.offset) { _, m in
                            MesajBalonu(ben: m["ben"].bool, gonderen: m["gonderen"].string, metin: m["mesaj"].string, saat: m["saat"].string).id(m["id"].int)
                        }
                        if durum["yaziyor"].bool { HStack { Text("Destek yazıyor…").font(.caption).foregroundStyle(.secondary); Spacer() } }
                    }
                    .padding(12)
                }
                .onChange(of: mesajlar.count) { _ in
                    if let s = mesajlar.last { withAnimation { kaydir.scrollTo(s["id"].int, anchor: .bottom) } }
                }
            }
            MesajCubugu(metin: $yazi, gonderiliyor: gonderiliyor) { Task { await gonder() } }
        }
        .navigationTitle("Canlı destek")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await yukle()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                await yukle()
            }
        }
    }

    private var durumMetni: String? {
        if durum["sira"].int > 0 { return "Sıradasınız: \(durum["sira"].int). sıra" }
        if durum["cevrimici"].isNull { return nil }
        return durum["cevrimici"].bool ? "Destek ekibi çevrimiçi" : "Destek ekibi şu an çevrimdışı; mesajınız iletilir, yanıt buraya gelir."
    }

    private func yukle() async {
        let son = mesajlar.last?["id"].int ?? 0
        do {
            let j = try await API.shared.cagir("destek", sorgu: son > 0 ? [("son", String(son))] : [])
            durum = j
            let var_ = Set(mesajlar.map { $0["id"].int })
            mesajlar += j["mesajlar"].array.filter { !var_.contains($0["id"].int) }
            hata = nil
        } catch { hata = error.localizedDescription }
    }

    private func gonder() async {
        let m = yazi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            try await API.shared.cagir("destek", govde: .form([("mesaj", m)]))
            yazi = ""
            await yukle()
        } catch { Toast.shared.goster(error.localizedDescription, hata: true) }
    }
}

/// Sorun çözüm: programdan KavisCloud'a bağlantının adım adım sınanması (GET tani)
struct TaniView: View {
    @State private var j: JSON = .null
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        List {
            Section {
                Button { Task { await sina() } } label: {
                    HStack { Label("Bağlantıyı sına", systemImage: "stethoscope"); Spacer(); if calisiyor { ProgressView() } }
                }
                .disabled(calisiyor)
            } footer: { Text("Program sunucusunun KavisCloud yönetim paneline ulaşıp ulaşamadığını adım adım denetler.") }
            if let h = hata { Section { Text(h).foregroundStyle(.red) } }
            if let e = j.str("engel") { Section("Sorun") { Text(e).foregroundStyle(.red) } }
            let adimlar = j["adimlar"].array
            if !adimlar.isEmpty {
                Section("Adımlar") {
                    ForEach(Array(adimlar.enumerated()), id: \.offset) { _, a in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: a["ok"].bool ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(a["ok"].bool ? Tema.renk("green") : Tema.renk("red"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a["ad"].string).font(.body.weight(.medium))
                                if let x = a.str("ayrinti") { Text(x).font(.caption).foregroundStyle(.secondary) }
                                if let o = a.str("oneri") { Text(o).font(.caption).foregroundStyle(Tema.renk("orange")) }
                            }
                        }
                    }
                }
            }
            if j["bilgi"].isObject {
                Section("Bilgi") {
                    LabeledContent("Program sürümü", value: j["bilgi"]["program"].string)
                    LabeledContent("PHP", value: j["bilgi"]["php"].string)
                    LabeledContent("Sunucu saati", value: j["bilgi"]["zaman"].string)
                    LabeledContent("Uygulama", value: "\(Config.appVersion) (\(Config.buildNumber))")
                }
            }
        }
        .navigationTitle("Bağlantı tanılama")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sina() async {
        calisiyor = true
        defer { calisiyor = false }
        do { j = try await API.shared.cagir("tani", zamanAsimi: 60); hata = nil } catch { hata = error.localizedDescription }
    }
}
