import AppKit
import QuotaCore
import SwiftUI

@main
struct QuotaApp: App {
    @NSApplicationDelegateAdaptor(QuotaAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRoot(appDelegate: appDelegate)
        }
    }
}

private struct SettingsRoot: View {
    @ObservedObject var appDelegate: QuotaAppDelegate

    var body: some View {
        if let session = appDelegate.session {
            SettingsView(session: session)
        } else {
            VStack(spacing: 8) {
                if let error = appDelegate.error {
                    Text("Headroom failed to start")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Starting Headroom…")
                }
            }
            .padding()
            .frame(width: 420, height: 200)
        }
    }
}

@MainActor
final class QuotaAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var session: AppSession?
    @Published private(set) var error: String?
    private let notifications = NotificationService()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.stop()
    }

    private func bootstrap() async {
        guard session == nil, error == nil else { return }
        do {
            let built = try await AppSession.makeDefault()
            session = built
            statusItemController = StatusItemController(
                session: built,
                notifications: notifications
            )
            built.start()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
