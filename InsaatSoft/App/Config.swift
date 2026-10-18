import Foundation
import UIKit

/// Uygulama sabitleri. KavisCloud adresi ve paket kimliği burada değiştirilir.
enum Config {
    /// KavisCloud yönetim paneli (Firma No ile firma adresini bulmak ve sürüm denetimi için)
    static let panelURL = URL(string: "https://cloudsoft.kavissoft.com")!

    static let appName = "İnşaatSoft ERP"

    /// KavisCloud > Uygulamalar'da iOS uygulaması bu kimlikle (Bundle ID) kayıtlı olmalıdır.
    /// Android uygulaması "com.kavissoft.insaatsoft" kullandığı için iOS ayrı bir kimlik kullanır
    /// (KavisCloud'da paket adı benzersizdir).
    /// Sabittir: uygulama başka bir imzayla (ör. Sideloadly / AltStore, değişen Bundle ID) kurulsa da KavisCloud bu kimlikle tanır.
    static let bundleID = "com.kavissoft.insaatsoft.ios"

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0" }
    static var buildNumber: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }

    /// Arka plan yenileme görevi (Info.plist > BGTaskSchedulerPermittedIdentifiers ile aynı olmalı)
    static let backgroundTaskID = "com.kavissoft.insaatsoft.ios.yenile"

    /// Sunucuya bildirilen cihaz adı (iOS 16+ gerçek cihaz adını vermez; model ve sürüm yazılır)
    static var deviceName: String {
        var sys = utsname()
        uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let ad = UIDevice.current.model   // "iPhone" / "iPad"
        return String("\(ad) (\(model)) · iOS \(UIDevice.current.systemVersion)".prefix(120))
    }

    /// Ön planda bildirim denetim aralığı (saniye)
    static let pollInterval: TimeInterval = 30
    /// Bu süreden uzun arka planda kalınırsa Face ID ile yeniden kilit açılır (saniye)
    static let relockAfter: TimeInterval = 300
}

/// Kalıcı, gizli olmayan ayarlar (firma adı ve adresi, son görülen bildirim vb.)
enum Store {
    private static let d = UserDefaults.standard

    static var firmaAd: String? { get { d.string(forKey: "firma_ad") } set { d.set(newValue, forKey: "firma_ad") } }
    static var firmaURL: String? { get { d.string(forKey: "firma_url") } set { d.set(newValue, forKey: "firma_url") } }
    static var firmaNo: String? { get { d.string(forKey: "firma_no") } set { d.set(newValue, forKey: "firma_no") } }
    static var sonEmail: String? { get { d.string(forKey: "son_email") } set { d.set(newValue, forKey: "son_email") } }
    static var biyometrikAcik: Bool { get { d.bool(forKey: "biyometrik_acik") } set { d.set(newValue, forKey: "biyometrik_acik") } }
    static var biyometrikSoruldu: Bool { get { d.bool(forKey: "biyometrik_soruldu") } set { d.set(newValue, forKey: "biyometrik_soruldu") } }
    static var erisimBitis: Double { get { d.double(forKey: "erisim_bitis") } set { d.set(newValue, forKey: "erisim_bitis") } }
    static var sonBildirim: Int { get { d.integer(forKey: "son_bildirim") } set { d.set(newValue, forKey: "son_bildirim") } }
    static var gorulenPopup: [Int] { get { (d.array(forKey: "gorulen_popup") as? [Int]) ?? [] } set { d.set(Array(newValue.suffix(200)), forKey: "gorulen_popup") } }
    static var gorulenVade: [String] { get { d.stringArray(forKey: "gorulen_vade") ?? [] } set { d.set(Array(newValue.suffix(500)), forKey: "gorulen_vade") } }

    static func firmayiUnut() {
        for k in ["firma_ad", "firma_url", "firma_no", "son_email", "biyometrik_acik", "biyometrik_soruldu", "erisim_bitis", "son_bildirim", "gorulen_popup", "gorulen_vade"] {
            d.removeObject(forKey: k)
        }
    }
}
