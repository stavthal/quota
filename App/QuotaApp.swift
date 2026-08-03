import QuotaCore
import SwiftUI

@main
struct QuotaApp: App {
    @StateObject private var sessionHolder = SessionHolder()
    private let notifications = NotificationService()

    var body: some Scene {
        MenuBarExtra {
            Group {
                if let session = sessionHolder.session {
                    PopoverView(
                        session: session,
                        notifications: notifications
                    )
                } else if let error = sessionHolder.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Headroom failed to start")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(width: 280)
                } else {
                    ProgressView("Starting Headroom…")
                        .padding()
                        .frame(width: 200)
                }
            }
            .task {
                await sessionHolder.bootstrap()
            }
        } label: {
            if let session = sessionHolder.session {
                MenuBarLabel(session: session)
            } else {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .accessibilityLabel("Headroom starting")
            }
        }
        .menuBarExtraStyle(.window)

        // Real window — MenuBarExtra sheets dismiss when focus moves (Keychain / network).
        Settings {
            if let session = sessionHolder.session {
                SettingsView(session: session)
            } else {
                ProgressView("Starting Headroom…")
                    .padding()
                    .frame(width: 420, height: 200)
            }
        }
    }
}

@MainActor
final class SessionHolder: ObservableObject {
    @Published var session: AppSession?
    @Published var error: String?
    private var didStart = false

    func bootstrap() async {
        guard session == nil, error == nil else {
            startIfNeeded()
            return
        }
        do {
            let built = try await AppSession.makeDefault()
            session = built
            startIfNeeded()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startIfNeeded() {
        guard !didStart, let session else { return }
        didStart = true
        session.start()
    }
}
