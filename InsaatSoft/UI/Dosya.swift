import SwiftUI
import UIKit
import QuickLook

/// İndirilen dosyaları önizleme (QuickLook: PDF, CSV, XML, görsel, HTML …) ve paylaşma / yazdırma
@MainActor
enum Paylasim {
    /// En üstteki görünüm denetleyicisi (sayfa ve uyarıların üstünden sunmak için)
    static func ust() -> UIViewController? {
        let pencere = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var v = pencere?.rootViewController
        while let p = v?.presentedViewController, !p.isBeingDismissed { v = p }
        return v
    }

    /// Dosyayı uygulama içinde açar; önizlenemeyen türlerde (yedek, zip …) paylaşım sayfası açılır
    static func onizle(_ yerel: URL) {
        guard let u = ust() else { return }
        if QLPreviewController.canPreview(yerel as NSURL) {
            u.present(TekDosyaOnizleme(yerel), animated: true)
        } else {
            paylas([yerel])
        }
    }

    /// Paylaşım sayfası (Dosyalar'a kaydet, AirDrop, e-posta, yazdır …)
    static func paylas(_ ogeler: [Any]) {
        guard let u = ust() else { return }
        let a = UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
        if let p = a.popoverPresentationController {
            p.sourceView = u.view
            p.sourceRect = CGRect(x: u.view.bounds.midX, y: u.view.bounds.midY, width: 1, height: 1)
            p.permittedArrowDirections = []
        }
        u.present(a, animated: true)
    }

    /// Sunucunun verdiği metni (ör. JSON listesi) dosya olarak paylaşır
    static func metinPaylas(_ metin: String, dosyaAdi: String) {
        let ad = dosyaAdi.replacingOccurrences(of: "/", with: "-")
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("paylasim", isDirectory: true)
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let u = klasor.appendingPathComponent(ad.isEmpty ? "dosya.txt" : ad)
        do {
            try metin.data(using: .utf8)?.write(to: u, options: .atomic)
            paylas([u])
        } catch {
            paylas([metin])
        }
    }

    static func kopyala(_ metin: String) {
        UIPasteboard.general.string = metin
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Toast.shared.goster("Panoya kopyalandı.")
    }
}

/// Tek dosyalık QuickLook önizlemesi (sağ üstte paylaş: kaydet, yazdır, gönder)
final class TekDosyaOnizleme: QLPreviewController, QLPreviewControllerDataSource {
    let dosya: URL

    init(_ dosya: URL) {
        self.dosya = dosya
        super.init(nibName: nil, bundle: nil)
        dataSource = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { dosya as NSURL }
}

// MARK: - İşlem sonucu sayfası (yeni parola, yedek kodlar, takvim bağlantısı, Authenticator anahtarı …)

struct SonucHedef: Identifiable {
    let id = UUID()
    let j: JSON
}

struct SonucView: View {
    let j: JSON
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Yigin { SonucGovde(j: j, kapat: { dismiss() }) }
            .interactiveDismissDisabled(j["kapatma_onayi"].bool)
    }
}

private struct SonucGovde: View {
    let j: JSON
    let kapat: () -> Void
    @StateObject private var eylem = EylemModel()
    @State private var buyukResim: GaleriOgesi?

    var body: some View {
        List {
            if let a = j.str("alt_baslik") {
                Text(a).font(.subheadline).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            let eylemler = Eylem.liste(j["eylemler"])
            if !eylemler.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(eylemler) { EylemCipi(e: $0) } }.padding(.horizontal, 16)
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
            BolumListesi(bolumler: j["bolumler"].array, buyukResim: $buyukResim)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(j.str("baslik") ?? "Sonuç")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat", action: kapat) } }
        .eylemKatmani(eylem)
        .fullScreenCover(item: $buyukResim) { GaleriGorunumu(oge: $0) }
    }
}
