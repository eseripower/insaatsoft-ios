import Foundation
import UIKit
import UserNotifications
import BackgroundTasks

/// Bildirimler:
///  - Uygulama açıkken her 30 sn'de "nabiz" sorulur; yeni bildirimler telefonda sesli bildirim olarak gösterilir.
///  - Arka planda iOS'un izin verdiği aralıklarla (BGAppRefreshTask) "nabiz" ve "vadeler" denetlenir.
///  - Bildirime dokunulunca ilgili ekran açılır.
@MainActor
final class Notifier: NSObject, ObservableObject {
    static let shared = Notifier()

    private var zamanlayici: Timer?
    private var sonVade = Date.distantPast

    // MARK: İzin

    func izinIste() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: Ön plan denetimi

    func baslat() {
        izinIste()
        durdur()
        Task { await denetle() }
        zamanlayici = Timer.scheduledTimer(withTimeInterval: Config.pollInterval, repeats: true) { _ in
            Task { @MainActor in await Notifier.shared.denetle() }
        }
    }

    func durdur() {
        zamanlayici?.invalidate()
        zamanlayici = nil
    }

    func denetle() async {
        guard Session.shared.asama == .hazir else { return }
        await Notifier.nabiz(goster: true)
        if Date().timeIntervalSince(sonVade) > 15 * 60 {
            sonVade = Date()
            await Notifier.vadeler()
        }
    }

    // MARK: Sunucu denetimleri (ön plan ve arka plan ortak)

    /// Yeni bildirimler. İlk çalıştırmada (son=0) yalnızca son kimlik öğrenilir, bildirim gösterilmez.
    static func nabiz(goster: Bool) async {
        let son = Store.sonBildirim
        guard let j = try? await API.shared.cagir("nabiz", sorgu: [("son", String(son))]) else { return }
        let yeniSon = j["son"].int
        if son > 0, goster {
            for b in j["bildirimler"].array.reversed() where b["id"].int > son {
                gonder(kimlik: "b\(b["id"].int)", baslik: b["baslik"].string, metin: b["mesaj"].string, ekran: b["ekran"].string)
            }
        }
        if yeniSon > son { Store.sonBildirim = yeniSon }
        let ok = j["okunmamis"].int, sh = j["sohbet"].int
        Session.shared.okunmamis = ok
        Session.shared.sohbetOkunmamis = sh
        if #available(iOS 17.0, *) { UNUserNotificationCenter.current().setBadgeCount(ok + sh) { _ in } }
        else { UIApplication.shared.applicationIconBadgeNumber = ok + sh }
    }

    /// Vadesi gelen ödemeler, çekler, taksitler, randevular (her biri bir kez bildirilir)
    static func vadeler() async {
        guard let j = try? await API.shared.cagir("vadeler") else { return }
        var gorulen = Store.gorulenVade
        let set = Set(gorulen)
        for k in j["kayitlar"].array {
            let a = k["anahtar"].string
            guard !a.isEmpty, !set.contains(a) else { continue }
            gonder(kimlik: "v-" + a, baslik: k["baslik"].string, metin: k["metin"].string, ekran: "")
            gorulen.append(a)
        }
        Store.gorulenVade = gorulen
    }

    static func gonder(kimlik: String, baslik: String, metin: String, ekran: String) {
        let c = UNMutableNotificationContent()
        c.title = baslik.isEmpty ? Config.appName : baslik
        c.body = metin
        c.sound = .default
        if !ekran.isEmpty { c.userInfo = ["ekran": ekran] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: kimlik, content: c, trigger: nil))
    }

    // MARK: Arka plan

    nonisolated static func arkaPlanKaydet() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Config.backgroundTaskID, using: nil) { gorev in
            guard let g = gorev as? BGAppRefreshTask else { gorev.setTaskCompleted(success: false); return }
            arkaPlanPlanla()
            let is_ = Task {
                await arkaPlanDenetim()
                g.setTaskCompleted(success: true)
            }
            g.expirationHandler = { is_.cancel() }
        }
    }

    nonisolated static func arkaPlanPlanla() {
        let r = BGAppRefreshTaskRequest(identifier: Config.backgroundTaskID)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    nonisolated static func arkaPlanDenetim() async {
        guard Store.firmaURL != nil, Keychain.yenileme != nil else { return }
        await nabiz(goster: true)
        await vadeler()
    }
}

// MARK: Bildirim gösterimi ve dokunma

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let ekran = response.notification.request.content.userInfo["ekran"] as? String ?? ""
        Task { @MainActor in
            Router.shared.bildirimdenAc(ekran.isEmpty ? "bildirimler" : ekran)
        }
        completionHandler()
    }
}
