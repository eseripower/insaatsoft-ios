import SwiftUI
import UIKit

// MARK: - Liste kalemi (sunucunun mk_kalem yapısı)

/// {id, baslik, alt, sag, renk, rozetler[{metin, renk}], satirlar[], ac{ekran|form,kayit}, eylemler[]}
struct Kalem: Identifiable {
    let id: String
    let j: JSON
    let baslik: String
    let alt: String
    let sag: String
    let renk: String
    let rozetler: [(String, String)]
    let satirlar: [String]
    let ac: Eylem?
    let eylemler: [Eylem]

    init(_ j: JSON, sira: Int) {
        self.j = j
        id = "\(sira)-\(j["id"].string)-\(j["baslik"].string)"
        baslik = j["baslik"].string
        alt = j["alt"].string
        sag = j["sag"].string
        renk = j["renk"].string
        rozetler = j["rozetler"].array.map { ($0["metin"].string, $0["renk"].string) }.filter { !$0.0.isEmpty }
        satirlar = j["satirlar"].stringArray
        ac = Eylem(j["ac"])
        eylemler = Eylem.liste(j["eylemler"])
    }

    static func liste(_ j: JSON) -> [Kalem] { j.array.enumerated().map { Kalem($0.element, sira: $0.offset) } }

    /// Sunucudaki kayıt numarası (toplu işlemlerde gönderilir)
    var sunucuId: String { j["id"].string }
}

struct Rozet: View {
    let metin: String
    let renk: String
    var body: some View {
        Text(metin)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(Tema.renk(renk))
            .background(Tema.renk(renk).opacity(0.13), in: Capsule())
    }
}

struct KalemSatiri: View {
    let k: Kalem
    var body: some View {
        if let r = k.j.str("resim") {
            HStack(spacing: 12) {
                YetkiliResim(adres: r).frame(width: 52, height: 52).background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 8))
                metin
            }
        } else {
            metin
        }
    }

    private var metin: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(k.baslik.isEmpty ? "—" : k.baslik).font(.body.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 4)
                if !k.sag.isEmpty {
                    Text(k.sag).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(k.renk.isEmpty ? Color.primary : Tema.renk(k.renk)).lineLimit(1)
                }
            }
            if !k.alt.isEmpty { Text(k.alt).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            ForEach(Array(k.satirlar.enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !k.rozetler.isEmpty {
                HStack(spacing: 6) { ForEach(Array(k.rozetler.enumerated()), id: \.offset) { _, r in Rozet(metin: r.0, renk: r.1) } }
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Özet kartı

struct OzetKarti: View {
    let j: JSON
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(j["baslik"].string).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(j["deger"].string).font(.title3.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(["", "slate"].contains(j["renk"].string) ? Color.primary : Tema.renk(j["renk"].string))
            if let a = j.str("alt") { Text(a).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Tema.renk(j["renk"].string)).frame(width: 3).padding(.vertical, 10)
        }
    }
}

struct Uyari: View {
    let metin: String
    let renk: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: renk == "red" ? "exclamationmark.triangle.fill" : "info.circle.fill")
            Text(metin).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Tema.renk(renk.isEmpty ? "blue" : renk))
        .padding(10)
        .background(Tema.renk(renk.isEmpty ? "blue" : renk).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Yükleniyor / hata / boş

struct YukleniyorView: View {
    var body: some View { ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct HataView: View {
    let mesaj: String
    let tekrar: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(mesaj).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Tekrar dene", action: tekrar).buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BosView: View {
    let mesaj: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(mesaj).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Bildirim balonu (toast)

final class Toast: ObservableObject {
    static let shared = Toast()
    @Published var mesaj: String?
    @Published var hata = false
    private var is_: DispatchWorkItem?

    func goster(_ m: String, hata: Bool = false) {
        DispatchQueue.main.async {
            self.mesaj = m
            self.hata = hata
            self.is_?.cancel()
            let w = DispatchWorkItem { [weak self] in withAnimation { self?.mesaj = nil } }
            self.is_ = w
            DispatchQueue.main.asyncAfter(deadline: .now() + (hata ? 4 : 2.5), execute: w)
        }
    }
}

struct ToastKatmani: ViewModifier {
    @ObservedObject var t = Toast.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = t.mesaj {
                HStack(spacing: 8) {
                    Image(systemName: t.hata ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    Text(m).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(t.hata ? Color(hex: "#b83a3a") : Tema.lacivert, in: Capsule())
                .shadow(radius: 8, y: 3)
                .padding(.bottom, 90).padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { withAnimation { t.mesaj = nil } }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: t.mesaj)
    }
}

// MARK: - Oturum anahtarıyla görsel

struct YetkiliResim: View {
    let adres: String
    var dolgu: ContentMode = .fill
    @State private var resim: UIImage?
    @State private var hata = false

    var body: some View {
        ZStack {
            if let r = resim {
                Image(uiImage: r).resizable().aspectRatio(contentMode: dolgu)
            } else if hata {
                Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .task(id: adres) {
            guard let u = API.shared.mutlak(adres) else { hata = true; return }
            if let d = try? await API.shared.veri(u), let r = UIImage(data: d) { resim = r } else { hata = true }
        }
    }
}

/// data:image/...;base64,... ya da https adresli görsel (KavisCloud pop-up görselleri)
struct DuzResim: View {
    let kaynak: String
    @State private var resim: UIImage?
    var body: some View {
        Group {
            if let r = resim { Image(uiImage: r).resizable().aspectRatio(contentMode: .fit) } else { Color.clear.frame(height: 1) }
        }
        .task(id: kaynak) {
            if kaynak.hasPrefix("data:"), let v = kaynak.range(of: "base64,") {
                if let d = Data(base64Encoded: String(kaynak[v.upperBound...]), options: .ignoreUnknownCharacters) { resim = UIImage(data: d) }
            } else if kaynak.hasPrefix("https://"), let u = URL(string: kaynak), let sonuc = try? await URLSession.shared.data(from: u) {
                resim = UIImage(data: sonuc.0)
            }
        }
    }
}

// MARK: - Yardımcılar

extension View {
    func kart() -> some View {
        padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SimgeKutusu: View {
    let ikon: String
    var renk: Color = Tema.altin
    var body: some View {
        Image(systemName: Simge.ad(ikon))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(renk.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
