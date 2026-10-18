import Foundation

/// Sunucunun {ok:false, kod, msg} yanıtları ve ağ hataları
struct APIError: LocalizedError {
    let kod: String
    let msg: String
    var status: Int = 0
    var yanit: JSON = .null
    var errorDescription: String? { msg }

    static func ag(_ e: Error) -> APIError {
        let ns = e as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return APIError(kod: "ag", msg: "İnternet bağlantısı yok. Bağlantınızı kontrol edip tekrar deneyin.")
            case NSURLErrorTimedOut:
                return APIError(kod: "ag", msg: "Sunucu zamanında yanıt vermedi. Biraz sonra tekrar deneyin.")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return APIError(kod: "ag", msg: "Sunucuya ulaşılamadı. Firma adresini ve internet bağlantınızı kontrol edin.")
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateNotYetValid, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return APIError(kod: "ssl", msg: "Güvenli bağlantı kurulamadı (SSL sertifikası). Sunucunun geçerli bir SSL sertifikası olmalı.")
            case NSURLErrorCancelled:
                return APIError(kod: "iptal", msg: "İstek iptal edildi.")
            default: break
            }
        }
        return APIError(kod: "ag", msg: "Bağlantı hatası: \(e.localizedDescription)")
    }
}

/// Genel oturum olayları (Session dinler)
extension Notification.Name {
    static let oturumBitti = Notification.Name("insaatsoft.oturumBitti")         // object: mesaj
    static let erisimEngellendi = Notification.Name("insaatsoft.erisimEngellendi") // object: mesaj
    static let parolaDegistirmeli = Notification.Name("insaatsoft.parolaDegistirmeli")
    static let veriDegisti = Notification.Name("insaatsoft.veriDegisti")         // form kaydedildi / işlem yapıldı: ekranlar yenilenir
}

/// multipart/form-data gövdesi (formlar ve dosya yükleme)
struct Multipart {
    let boundary = "----InsaatSoftiOS" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private(set) var data = Data()

    private mutating func yaz(_ s: String) { data.append(s.data(using: .utf8)!) }
    private func kacis(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "") }

    mutating func add(_ name: String, _ value: String) {
        yaz("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(kacis(name))\"\r\n\r\n\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mime: String, content: Data) {
        yaz("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(kacis(name))\"; filename=\"\(kacis(filename))\"\r\nContent-Type: \(mime)\r\n\r\n")
        data.append(content)
        yaz("\r\n")
    }

    func bitir() -> Data {
        var d = data
        d.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return d
    }
}

enum Govde {
    case yok
    case form([(String, String)])
    case json([String: Any])
    case multipart(Multipart)
}

/// İnşaatSoft mobil API istemcisi: /api/v1/index.php?r=<uç>
/// Erişim anahtarı 30 dakikalıktır; süresi dolunca yenileme anahtarıyla (dönüşümlü) yenilenir.
/// Yenileme anahtarı her kullanımda değiştiği için aynı anda iki yenileme yapılmaz (sunucu bunu çalınma sayar).
final class API {
    static let shared = API()

    private let session: URLSession
    private let yenileyici = Yenileyici()
    private let resimOnbellek = NSCache<NSString, NSData>()

    private init() {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 180
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.httpAdditionalHeaders = ["User-Agent": "InsaatSoft-iOS/\(Config.appVersion) (\(Config.buildNumber))", "Accept": "application/json"]
        session = URLSession(configuration: c)
        resimOnbellek.totalCostLimit = 60 * 1024 * 1024
    }

    // MARK: Adres

    var tabanURL: URL? {
        guard let s = Store.firmaURL, var c = URLComponents(string: s) else { return nil }
        if c.path.hasSuffix("/") { c.path.removeLast() }
        return c.url
    }

    static let guvenliKarakter: CharacterSet = {
        var s = CharacterSet()
        s.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s
    }()

    static func kodla(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: guvenliKarakter) ?? s }

    static func sorgu(_ q: [(String, String)]) -> String {
        q.map { kodla($0.0) + "=" + kodla($0.1) }.joined(separator: "&")
    }

    func url(_ uc: String, _ sorgu: [(String, String)] = []) -> URL? {
        guard let t = tabanURL else { return nil }
        let q = API.sorgu([("r", uc)] + sorgu)
        return URL(string: t.absoluteString + "/api/v1/index.php?" + q)
    }

    /// Sunucunun verdiği mutlak adres (görsel vb.). Firma adresi https ise http adresler https'e yükseltilir.
    func mutlak(_ s: String) -> URL? {
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http://"), tabanURL?.scheme == "https" { return URL(string: "https://" + s.dropFirst(7)) }
        if s.hasPrefix("http") { return URL(string: s) }
        guard let t = tabanURL else { return nil }
        return URL(string: t.absoluteString + (s.hasPrefix("/") ? "" : "/") + s)
    }

    // MARK: İstek

    /// Ham istek: yanıtı ok:false olsa da döndürür (giriş akışı için). Ağ hatasında APIError atar.
    func ham(_ uc: String, sorgu: [(String, String)] = [], govde: Govde = .yok, kimlik: Bool = true, zamanAsimi: TimeInterval? = nil) async throws -> (JSON, Int) {
        guard let u = url(uc, sorgu) else { throw APIError(kod: "firma", msg: "Firma adresi tanımlı değil.") }
        if kimlik, Store.erisimBitis > 0, Date().timeIntervalSince1970 > Store.erisimBitis, Keychain.yenileme != nil {
            _ = await yenileyici.yenile()
        }
        var (j, kod) = try await gonder(u, govde: govde, kimlik: kimlik, zamanAsimi: zamanAsimi)
        // Erişim anahtarının süresi dolmuş: bir kez yenileyip tekrar dene
        if kimlik, kod == 401, j["kod"].string == "oturum" {
            switch await yenileyici.yenile() {
            case .tamam:
                (j, kod) = try await gonder(u, govde: govde, kimlik: kimlik, zamanAsimi: zamanAsimi)
            case .reddedildi(let m):
                NotificationCenter.default.post(name: .oturumBitti, object: m)
            case .ag:
                break
            }
        }
        if kimlik { genelDurum(j) }
        return (j, kod)
    }

    /// Normal istek: ok:false ise APIError atar
    @discardableResult
    func cagir(_ uc: String, sorgu: [(String, String)] = [], govde: Govde = .yok, zamanAsimi: TimeInterval? = nil) async throws -> JSON {
        let (j, kod) = try await ham(uc, sorgu: sorgu, govde: govde, kimlik: true, zamanAsimi: zamanAsimi)
        if j["ok"].bool { return j }
        throw APIError(kod: j["kod"].string.isEmpty ? "hata" : j["kod"].string,
                       msg: j.str("msg") ?? "İşlem yapılamadı (HTTP \(kod)).", status: kod, yanit: j)
    }

    private func gonder(_ u: URL, govde: Govde, kimlik: Bool, zamanAsimi: TimeInterval?) async throws -> (JSON, Int) {
        var r = URLRequest(url: u)
        if let z = zamanAsimi { r.timeoutInterval = z }
        switch govde {
        case .yok:
            r.httpMethod = "GET"
        case .form(let alanlar):
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = API.sorgu(alanlar).data(using: .utf8)
        case .json(let d):
            r.httpMethod = "POST"
            r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: d)
        case .multipart(let m):
            r.httpMethod = "POST"
            r.setValue("multipart/form-data; boundary=\(m.boundary)", forHTTPHeaderField: "Content-Type")
            r.httpBody = m.bitir()
        }
        if kimlik, let t = Keychain.erisim { r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await session.data(for: r)
            let kod = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let j = JSON.parse(data), j.isObject else {
                throw APIError(kod: "yanit", msg: kod >= 500 ? "Sunucu hatası (HTTP \(kod)). Biraz sonra tekrar deneyin."
                    : "Sunucudan beklenmeyen yanıt geldi (HTTP \(kod)). Firma adresi doğru mu?", status: kod)
            }
            return (j, kod)
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.ag(error)
        }
    }

    /// Erişimi kesen yanıtlar uygulamanın tamamını etkiler
    private func genelDurum(_ j: JSON) {
        guard !j["ok"].bool else { return }
        switch j["kod"].string {
        case "cihaz_engel", "lisans", "kapali":
            NotificationCenter.default.post(name: .erisimEngellendi, object: j.str("msg") ?? "Erişim kapatıldı.")
        case "parola_degistir":
            NotificationCenter.default.post(name: .parolaDegistirmeli, object: nil)
        default: break
        }
    }

    // MARK: Oturum anahtarları

    func anahtarlariKaydet(_ j: JSON) {
        if let e = j.str("erisim") { Keychain.erisim = e }
        if let y = j.str("yenileme") { Keychain.yenileme = y }
        if let s = j.str("cihaz_sirri") { Keychain.cihazSirri = s }
        let sure = j["erisim_suresi"].int
        Store.erisimBitis = Date().timeIntervalSince1970 + Double(sure > 120 ? sure - 60 : 1700)
    }

    enum YenilemeSonucu { case tamam, reddedildi(String), ag }

    /// Arka planda ya da açılışta oturumu yenilemek için
    func oturumuYenile() async -> YenilemeSonucu { await yenileyici.yenile() }

    fileprivate func yenilemeIstegi() async -> YenilemeSonucu {
        guard let y = Keychain.yenileme else { return .reddedildi("Oturumunuz sona erdi, yeniden giriş yapın.") }
        do {
            let (j, _) = try await ham("yenile", govde: .form([("cihaz_kimlik", Keychain.cihazKimlik), ("yenileme", y)]), kimlik: false)
            if j["ok"].bool {
                anahtarlariKaydet(j)
                return .tamam
            }
            Keychain.oturumuSil()
            if j["kod"].string == "cihaz_engel" { NotificationCenter.default.post(name: .erisimEngellendi, object: j.str("msg") ?? "Erişim kapatıldı.") }
            return .reddedildi(j.str("msg") ?? "Oturumunuz sona erdi, yeniden giriş yapın.")
        } catch let e as APIError {
            return e.kod == "ag" || e.kod == "ssl" || e.status >= 500 || e.status == 0 ? .ag : .reddedildi(e.msg)
        } catch {
            return .ag
        }
    }

    // MARK: Görseller (oturum anahtarıyla)

    func veri(_ url: URL) async throws -> Data {
        if let d = resimOnbellek.object(forKey: url.absoluteString as NSString) { return d as Data }
        func iste() async throws -> (Data, Int, String) {
            var r = URLRequest(url: url)
            if let t = Keychain.erisim { r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
            let (d, resp) = try await session.data(for: r)
            let h = resp as? HTTPURLResponse
            return (d, h?.statusCode ?? 0, h?.value(forHTTPHeaderField: "Content-Type") ?? "")
        }
        do {
            var (d, kod, tur) = try await iste()
            if kod == 401 {
                if case .tamam = await yenileyici.yenile() { (d, kod, tur) = try await iste() }
            }
            guard kod == 200, !tur.contains("json") else {
                throw APIError(kod: "yok", msg: JSON.parse(d)?.str("msg") ?? "Dosya açılamadı (HTTP \(kod)).", status: kod)
            }
            resimOnbellek.setObject(d as NSData, forKey: url.absoluteString as NSString, cost: d.count)
            return d
        } catch let e as APIError { throw e } catch { throw APIError.ag(error) }
    }

    func onbellegiTemizle() { resimOnbellek.removeAllObjects() }

    // MARK: İmzalı indirme (dosya, CSV, e-belge XML, yedek)

    /// İmzalı adresteki dosyayı geçici klasöre indirir; sunucunun verdiği dosya adıyla yerel adresini döndürür.
    func indir(_ url: URL) async throws -> URL {
        var r = URLRequest(url: url)
        r.timeoutInterval = 300
        r.setValue("*/*", forHTTPHeaderField: "Accept")
        do {
            let (gecici, resp) = try await session.download(for: r)
            let h = resp as? HTTPURLResponse
            let kod = h?.statusCode ?? 0
            let tur = h?.value(forHTTPHeaderField: "Content-Type") ?? ""
            if kod != 200 {
                let d = (try? Data(contentsOf: gecici)) ?? Data()
                let m = JSON.parse(d)?.str("msg") ?? String(decoding: d.prefix(400), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw APIError(kod: "indir", msg: m.isEmpty || m.hasPrefix("<") ? "Dosya indirilemedi (HTTP \(kod))." : m, status: kod)
            }
            let ad = API.dosyaAdi(h?.value(forHTTPHeaderField: "Content-Disposition"), tur: tur)
            let fm = FileManager.default
            let klasor = fm.temporaryDirectory.appendingPathComponent("indirilen", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: klasor, withIntermediateDirectories: true)
            let hedef = klasor.appendingPathComponent(ad)
            if fm.fileExists(atPath: hedef.path) { try? fm.removeItem(at: hedef) }
            try fm.moveItem(at: gecici, to: hedef)
            return hedef
        } catch let e as APIError { throw e } catch { throw APIError.ag(error) }
    }

    /// Content-Disposition başlığından dosya adı (filename* öncelikli); yoksa içerik türüne göre
    static func dosyaAdi(_ baslik: String?, tur: String) -> String {
        var ad = ""
        if let b = baslik {
            for parca in b.components(separatedBy: ";") {
                let p = parca.trimmingCharacters(in: .whitespaces)
                if p.lowercased().hasPrefix("filename*=") {
                    var v = String(p.dropFirst(10))
                    if let i = v.range(of: "''") { v = String(v[i.upperBound...]) }
                    if let c = v.removingPercentEncoding, !c.isEmpty { ad = c; break }
                } else if p.lowercased().hasPrefix("filename="), ad.isEmpty {
                    ad = String(p.dropFirst(9)).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                }
            }
        }
        ad = ad.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-").replacingOccurrences(of: ":", with: "-")
        if ad.isEmpty || ad.hasPrefix(".") {
            let t = tur.lowercased()
            let uzanti = t.contains("csv") ? "csv" : t.contains("pdf") ? "pdf" : t.contains("zip") ? "zip" : t.contains("xml") ? "xml" : t.contains("html") ? "html"
                : t.contains("jpeg") ? "jpg" : t.contains("png") ? "png" : t.contains("gzip") ? "gz" : t.contains("sql") ? "sql" : t.contains("text") ? "txt" : "bin"
            ad = "dosya." + uzanti
        }
        return ad
    }
}

/// Yenileme isteklerini sıraya koyar: aynı anda yalnızca bir yenileme yapılır, bekleyenler aynı sonucu alır.
private actor Yenileyici {
    private var gorev: Task<API.YenilemeSonucu, Never>?

    func yenile() async -> API.YenilemeSonucu {
        if let g = gorev { return await g.value }
        let g = Task { await API.shared.yenilemeIstegi() }
        gorev = g
        let s = await g.value
        gorev = nil
        return s
    }
}
