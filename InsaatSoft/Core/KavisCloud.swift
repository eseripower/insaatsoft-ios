import Foundation

/// KavisCloud yönetim panelinin herkese açık mobil uçları:
///  POST /api/v1/mobile/lookup   Firma No → firma adı ve program adresi (+ uygulama sürüm bilgisi)
///  POST /api/v1/mobile/version  uygulamanın güncel ve desteklenen en düşük sürümü (iOS: App Store adresi)
enum KavisCloud {
    struct Firma {
        let ad: String
        let url: String
        let firmaNo: String
        let surum: SurumBilgisi
    }

    struct SurumBilgisi {
        let guncel: String
        let enDusuk: String
        let indirme: String

        var zorunluGuncelleme: Bool { !enDusuk.isEmpty && KavisCloud.karsilastir(Config.appVersion, enDusuk) < 0 }
        var yeniSurumVar: Bool { !guncel.isEmpty && KavisCloud.karsilastir(Config.appVersion, guncel) < 0 }
    }

    static func firmaBul(_ no: String) async throws -> Firma {
        let j = try await istek("api/v1/mobile/lookup", ["business_no": no, "package": Config.bundleID, "version": Config.appVersion])
        let url = j["url"].string
        guard !url.isEmpty else { throw APIError(kod: "yok", msg: "Firma adresi alınamadı.") }
        return Firma(ad: j["name"].string, url: url, firmaNo: j.str("business_no") ?? no, surum: surum(j))
    }

    static func surumDenetle() async -> SurumBilgisi? {
        guard let j = try? await istek("api/v1/mobile/version", ["package": Config.bundleID, "version": Config.appVersion]) else { return nil }
        return surum(j)
    }

    private static func surum(_ j: JSON) -> SurumBilgisi {
        SurumBilgisi(guncel: j["version"].string, enDusuk: j["min_version"].string, indirme: j["download_url"].string)
    }

    private static func istek(_ yol: String, _ govde: [String: String]) async throws -> JSON {
        var r = URLRequest(url: Config.panelURL.appendingPathComponent(yol))
        r.httpMethod = "POST"
        r.timeoutInterval = 12
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.httpBody = try? JSONSerialization.data(withJSONObject: govde)
        let data: Data, kod: Int
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            data = d
            kod = (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw APIError.ag(error)
        }
        let j = JSON.parse(data) ?? .null
        if kod == 200, j["ok"].bool { return j }
        let m = j.str("error") ?? j.str("message") ?? (kod == 429 ? "Çok sayıda deneme yapıldı. Bir süre sonra tekrar deneyin."
            : kod == 404 ? "Bu firma numarasıyla kayıtlı bir firma bulunamadı." : "KavisCloud'a ulaşılamadı (HTTP \(kod)).")
        throw APIError(kod: j["kod"].string.isEmpty ? "hata" : j["kod"].string, msg: m, status: kod)
    }

    /// "1.2.10" ile "1.2.9" gibi sürümleri karşılaştırır: <0 a eski, 0 eşit, >0 a yeni
    static func karsilastir(_ a: String, _ b: String) -> Int {
        let x = a.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
        let y = b.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? -1 : 1 }
        }
        return 0
    }
}
