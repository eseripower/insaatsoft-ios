import SwiftUI
import UIKit
import UserNotifications

@main
struct InsaatSoftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = Session.shared
    @StateObject private var router = Router.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            KokView()
                .environmentObject(session)
                .environmentObject(router)
                .modifier(ToastKatmani())
                .tint(Tema.altin)
                // Uygulama değiştiricide ekran içeriği görünmesin (finansal veriler)
                .overlay { if scenePhase != .active && session.asama == .hazir { GizlilikPerdesi() } }
                .task { if session.asama == .aciliyor { await session.baslat() } }
        }
        .onChange(of: scenePhase) { faz in
            switch faz {
            case .background:
                session.arkaPlanaGecti()
                Notifier.arkaPlanPlanla()
            case .active:
                session.onPlanaGeldi()
            default: break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = Notifier.shared
        Notifier.arkaPlanKaydet()
        return true
    }
}

struct KokView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            switch session.asama {
            case .aciliyor: AcilisView()
            case .firma: FirmaView()
            case .giris: GirisView()
            case .kilitli: KilitView()
            case .parolaDegistir: ParolaDegistirView()
            case .hazir: AnaView()
            case .engelli(let m): EngelView(mesaj: m)
            case .guncelle(let g): GuncelleView(bilgi: g)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.asama)
    }
}

struct AcilisView: View {
    var body: some View {
        ZStack {
            Tema.lacivert.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                ProgressView().tint(Tema.altin)
            }
        }
    }
}

struct GizlilikPerdesi: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            Image("Logo").resizable().scaledToFit().frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
