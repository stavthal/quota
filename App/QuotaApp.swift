import QuotaCore
import SwiftUI

@main
struct QuotaApp: App {
    @StateObject private var sessionHolder = SessionHolder()
    @State private var showingSettings = false
    private let notifications = NotificationService()

    var body: some Scene {
        MenuBarExtra {
            Group {
                if let session = sessionHolder.session {
                    PopoverView(
                        session: session,
                        showingSettings: $showingSettings,
                        notifications: notifications
                    )
                    .sheet(isPresented: $showingSettings) {
                        SettingsView(session: session)
                    }
                } else if let error = sessionHolder.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quota failed to start")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(width: 280)
                } else {
                    ProgressView("Starting Quota…")
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
                    .accessibilityLabel("Quota starting")
            }
        }
        .menuBarExtraStyle(.window)
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
