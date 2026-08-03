import Charts
import QuotaCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var session: AppSession
    let notifications: NotificationService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().opacity(0.35)
            ForEach(ProviderID.allCases) { id in
                ProviderRow(
                    providerID: id,
                    snapshot: session.snapshots[id],
                    auth: session.authStatuses[id] ?? .signedOut,
                    error: session.lastErrors[id]
                )
            }
            Divider().opacity(0.35)
            footer
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .task {
            await session.refreshAll()
            let events = session.consumeAlertEvents()
            await notifications.deliver(events: events, preferences: session.preferences)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quota")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Local AI usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: QuotaTheme.symbol(for: session.aggregateSeverity))
                .foregroundStyle(QuotaTheme.color(for: session.aggregateSeverity))
                .font(.title2)
                .accessibilityLabel(accessibilitySummary)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task {
                    await session.refreshAll()
                    let events = session.consumeAlertEvents()
                    await notifications.deliver(events: events, preferences: session.preferences)
                }
            } label: {
                Label(session.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(session.isRefreshing)

            Spacer()

            Button("Settings…") {
                openSettings()
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    private var accessibilitySummary: String {
        "Quota status \(session.aggregateSeverity.rawValue)"
    }
}

private struct ProviderRow: View {
    let providerID: ProviderID
    let snapshot: UsageSnapshot?
    let auth: AuthStatus
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(authLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(QuotaTheme.critical)
            } else if case .signedOut = auth {
                Text("Not bound — open Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let snapshot {
                ForEach(snapshot.windows) { window in
                    WindowMeter(window: window)
                }
                if !snapshot.models.isEmpty {
                    Chart(snapshot.models) { model in
                        BarMark(
                            x: .value("Amount", model.amount),
                            y: .value("Model", model.label)
                        )
                        .foregroundStyle(QuotaTheme.accent.opacity(0.85))
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(snapshot.models.count) * 22)
                    .accessibilityLabel("Model breakdown")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        switch providerID {
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }

    private var authLabel: String {
        switch auth {
        case .signedOut: "Signed out"
        case .signedIn(let hint): hint ?? "Signed in"
        case .expired: "Expired"
        case .invalid: "Invalid"
        }
    }
}

private struct WindowMeter: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(kindLabel)
                    .font(.caption)
                Spacer()
                Text("\(Int(window.utilization * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(meterColor)
            }
            ProgressView(value: window.utilization)
                .tint(meterColor)
            Text("Resets \(window.resetsAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var kindLabel: String {
        switch window.kind {
        case .cursorAuto: "Cursor models"
        case .cursorAPI: "API models"
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .custom: "Custom"
        }
    }

    private var meterColor: Color {
        if window.utilization >= 0.9 { return QuotaTheme.critical }
        if window.utilization >= 0.8 { return QuotaTheme.warn }
        return QuotaTheme.accent
    }
}
