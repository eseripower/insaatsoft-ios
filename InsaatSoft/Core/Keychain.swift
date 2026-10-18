import Foundation
import Security

/// Oturum anahtarları, cihaz sırrı ve cihaz kimliği iOS Anahtar Zinciri'nde saklanır.
/// Erişilebilirlik: "ilk kilit açılışından sonra, yalnızca bu cihaz" — arka plan bildirim denetimi çalışabilsin,
/// ama iCloud yedeğine / başka cihaza taşınmasın.
enum Keychain {
    private static let service = "com.kavissoft.insaatsoft.ios.oturum"

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: Kısayollar

    static var erisim: String? { get { get("erisim") } set { set("erisim", newValue) } }
    static var yenileme: String? { get { get("yenileme") } set { set("yenileme", newValue) } }
    static var cihazSirri: String? { get { get("cihaz_sirri") } set { set("cihaz_sirri", newValue) } }

    /// Uygulamanın ürettiği kalıcı cihaz kimliği (sunucu kuralı: [A-Za-z0-9_.:-]{8,80})
    static var cihazKimlik: String {
        if let k = get("cihaz_kimlik"), !k.isEmpty { return k }
        let k = "ios-" + UUID().uuidString.lowercased()
        set("cihaz_kimlik", k)
        return k
    }

    static func oturumuSil() {
        erisim = nil
        yenileme = nil
        Store.erisimBitis = 0
    }

    static func hepsiniSil() {
        oturumuSil()
        cihazSirri = nil
    }
}
