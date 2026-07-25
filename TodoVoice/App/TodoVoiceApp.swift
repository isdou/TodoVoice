import SwiftUI
import SwiftData
import UserNotifications

@main
struct TodoVoiceApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([TodoItem.self])
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: [configuration]
            )
        } catch {
            print("SwiftData init failed: \(error), cleaning and recreating...")
            // 彻底删除所有数据库文件
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            if let dir = appSupport {
                let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                for url in items ?? [] {
                    if url.lastPathComponent.hasPrefix("default.store") {
                        try? fm.removeItem(at: url)
                    }
                }
            }
            // 再试一次，如果还失败用内存数据库保底
            do {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                print("SwiftData fallback to in-memory: \(error)")
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: schema, configurations: [config])
            }
        }
    }

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
