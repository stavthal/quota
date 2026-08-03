import QuotaCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var session: AppSession
    let notifications: NotificationService
    @Environment(\.openSettings) private var openSettings

    private var visibleIDs: [ProviderID] {
        session.preferences.visibleProviderIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().opacity(0.35)

            if visibleIDs.isEmpty {
                Text("All AIs are hidden. Open Settings to show one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(visibleIDs) { id in
                        ProviderCard(
                            providerID: id,
                            snapshot: session.snapshots[id],
                            auth: session.authStatuses[id] ?? .signedOut,
                            error: session.lastErrors[id],
                            trackingEnabled: session.preferences.isTrackingEnabled(for: id)
                        )
                    }
                }
            }

            Divider().opacity(0.35)
            footer
        }
        .padding(16)
        .frame(width: max(340, CGFloat(max(visibleIDs.count, 1)) * 148 + 32))
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
                Text("Headroom")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Local AI usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: QuotaTheme.symbol(for: session.aggregateSeverity))
                .foregroundStyle(QuotaTheme.color(for: session.aggregateSeverity))
                .font(.title2)
                .accessibilityLabel("Headroom status \(session.aggregateSeverity.rawValue)")
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
}

private struct ProviderCard: View {
    let providerID: ProviderID
    let snapshot: UsageSnapshot?
    let auth: AuthStatus
    let error: String?
    let trackingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderIconView(providerID: providerID, size: 22)
                Text(providerID.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(QuotaTheme.critical)
                    .lineLimit(3)
            } else if !trackingEnabled {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Enable in Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if case .signedOut = auth {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Enable in Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let snapshot {
                ForEach(snapshot.windows.prefix(2)) { window in
                    CompactMeter(window: window)
                }
            } else {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CompactMeter: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueLabel)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(meterColor)
            }
            ProgressView(value: window.utilization)
                .tint(meterColor)
        }
    }

    private var valueLabel: String {
        if window.unit == .credits {
            return "\(Int(window.used))/\(Int(window.limit))"
        }
        return "\(Int(window.utilization * 100))%"
    }

    private var kindLabel: String {
        switch window.kind {
        case .cursorAuto: "Models"
        case .cursorAPI: "API"
        case .fiveHour: "5h"
        case .weekly: "Week"
        case .monthly: "Month"
        case .copilotCredits: "Credits"
        case .custom: "On-demand"
        }
    }

    private var meterColor: Color {
        if window.utilization >= 0.9 { return QuotaTheme.critical }
        if window.utilization >= 0.8 { return QuotaTheme.warn }
        return QuotaTheme.accent
    }
}
