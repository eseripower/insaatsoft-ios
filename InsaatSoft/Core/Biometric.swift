import Foundation
import LocalAuthentication
import Security

/// Face ID / Touch ID ile giriş.
/// Secure Enclave içinde biyometri korumalı bir ECDSA P-256 anahtar çifti üretilir; açık anahtar sunucuya kaydedilir.
/// Her girişte sunucunun verdiği tek kullanımlık meydan okuma (challenge) bu anahtarla imzalanır.
/// Özel anahtar cihazdan hiç çıkmaz; yüz / parmak izi verisi sunucuya gitmez. (inc/mobil.php ile aynı tasarım)
enum Biometric {
    private static var tag: Data { (Config.bundleID + ".biyometrik").data(using: .utf8)! }

    static var kullanilabilir: Bool {
        var e: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
    }

    static var ad: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biyometrik doğrulama"
        }
    }

    static var simge: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return c.biometryType == .touchID ? "touchid" : "faceid"
    }

    static var anahtarVar: Bool { anahtar(baglam: nil) != nil }

    /// Yeni anahtar çifti üretir (eskisi silinir) ve açık anahtarı SPKI DER, base64 olarak döndürür
    static func anahtarUret() throws -> String {
        anahtariSil()
        var err: Unmanaged<CFError>?
        guard let erisim = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet], &err) else {
            throw hata(err, "Erişim denetimi oluşturulamadı.")
        }
        let nitelik: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: erisim,
            ] as [String: Any],
        ]
        guard let ozel = SecKeyCreateRandomKey(nitelik as CFDictionary, &err) else {
            throw hata(err, "Güvenli anahtar oluşturulamadı. Cihazda ekran kodu ve \(ad) etkin olmalı.")
        }
        guard let acik = SecKeyCopyPublicKey(ozel), let ham = SecKeyCopyExternalRepresentation(acik, &err) as Data? else {
            throw hata(err, "Açık anahtar alınamadı.")
        }
        // X9.63 (04|X|Y, 65 bayt) → SubjectPublicKeyInfo (prime256v1)
        let spkiBasi: [UInt8] = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
                                 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00]
        return (Data(spkiBasi) + ham).base64EncodedString()
    }

    static func anahtariSil() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ]
        SecItemDelete(q as CFDictionary)
    }

    /// Kullanıcıdan Face ID / Touch ID ister ve metni imzalar (ECDSA-SHA256, DER). base64 imza döndürür.
    static func imzala(_ metin: String, neden: String) async throws -> String {
        let baglam = LAContext()
        baglam.localizedCancelTitle = "Vazgeç"
        baglam.localizedFallbackTitle = ""
        do {
            _ = try await baglam.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: neden)
        } catch let e as LAError {
            switch e.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                throw APIError(kod: "iptal", msg: "Doğrulama iptal edildi.")
            case .biometryLockout:
                throw APIError(kod: "kilit", msg: "\(ad) çok fazla hatalı deneme nedeniyle kilitlendi. Parolanızla giriş yapın.")
            case .biometryNotEnrolled, .biometryNotAvailable:
                throw APIError(kod: "yok", msg: "\(ad) bu cihazda kullanılamıyor.")
            default:
                throw APIError(kod: "biyometrik", msg: "\(ad) doğrulanamadı.")
            }
        }
        guard let k = anahtar(baglam: baglam) else {
            throw APIError(kod: "biyometrik_yok", msg: "Bu cihazdaki \(ad) anahtarı bulunamadı (\(ad) ayarları değişmiş olabilir). Parolanızla giriş yapın.")
        }
        let veri = Data(metin.utf8)
        return try await Task.detached(priority: .userInitiated) {
            var err: Unmanaged<CFError>?
            guard let imza = SecKeyCreateSignature(k, .ecdsaSignatureMessageX962SHA256, veri as CFData, &err) as Data? else {
                throw Biometric.hata(err, "İmza oluşturulamadı.")
            }
            return imza.base64EncodedString()
        }.value
    }

    private static func anahtar(baglam: LAContext?) -> SecKey? {
        var q: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        if let baglam { q[kSecUseAuthenticationContext as String] = baglam } else {
            // Yalnızca varlık denetimi: kullanıcıdan doğrulama istenmez
            let c = LAContext()
            c.interactionNotAllowed = true
            q[kSecUseAuthenticationContext as String] = c
        }
        var out: AnyObject?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        guard s == errSecSuccess || s == errSecInteractionNotAllowed, let o = out else { return nil }
        return (o as! SecKey)
    }

    private static func hata(_ e: Unmanaged<CFError>?, _ m: String) -> APIError {
        if let e { _ = e.takeRetainedValue() }
        return APIError(kod: "anahtar", msg: m)
    }
}
