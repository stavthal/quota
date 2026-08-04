import AppKit
import QuotaCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var session: AppSession
    let notifications: NotificationService
    @Environment(\.openSettings) private var openSettings

    private var visibleIDs: [ProviderID] {
        session.preferences.visibleProviderIDs
    }

    /// Providers plus OpenCode’s top backends (inserted after the OpenCode card).
    private var gridItems: [PopoverGridItem] {
        var items: [PopoverGridItem] = []
        for id in visibleIDs {
            let titleOverride = id == .opencode ? session.openCodeSubscriptionLabel : nil
            items.append(.provider(id, titleOverride: titleOverride))
            if id == .opencode {
                let showBackends: Bool = {
                    guard session.preferences.isTrackingEnabled(for: .opencode) else { return false }
                    if case .signedIn = session.authStatuses[.opencode] { return true }
                    return false
                }()
                if showBackends {
                    for backend in session.openCodeBackends.prefix(OpenCodeLocalUsageReader.maxBackends) {
                        items.append(.openCodeBackend(backend))
                    }
                }
            }
        }
        return items
    }

    /// Cap at 4 columns; 5+ cards wrap to a second row.
    private var columnCount: Int {
        min(max(gridItems.count, 1), Self.maxColumns)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: Self.cardMinWidth), spacing: Self.gridSpacing),
            count: columnCount
        )
    }

    private var popoverWidth: CGFloat {
        let columns = CGFloat(columnCount)
        let content = columns * Self.cardMinWidth + max(0, columns - 1) * Self.gridSpacing
        return max(Self.minPopoverWidth, content + Self.horizontalPadding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().opacity(0.35)

            if gridItems.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Self.gridSpacing) {
                    ForEach(gridItems) { item in
                        switch item {
                        case .provider(let id, let titleOverride):
                            ProviderCard(
                                providerID: id,
                                titleOverride: titleOverride,
                                snapshot: session.snapshots[id],
                                auth: session.authStatuses[id] ?? .signedOut,
                                error: session.lastErrors[id],
                                trackingEnabled: session.preferences.isTrackingEnabled(for: id)
                            )
                        case .openCodeBackend(let backend):
                            OpenCodeBackendCard(backend: backend)
                        }
                    }
                }
            }

            Divider().opacity(0.35)
            footer
        }
        .padding(16)
        .frame(width: popoverWidth)
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
            Spacer(minLength: 12)
            Image(systemName: QuotaTheme.symbol(for: session.aggregateSeverity))
                .foregroundStyle(QuotaTheme.color(for: session.aggregateSeverity))
                .font(.title2)
                .accessibilityLabel("Headroom status \(session.aggregateSeverity.rawValue)")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("All AIs are hidden")
                .font(.subheadline.weight(.medium))
            Text("Open Settings to show one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 12) {
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

            Spacer(minLength: 8)

            Button("Settings…") {
                openSettings()
                NSApp.activate()
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    private static let maxColumns = 4
    private static let cardMinWidth: CGFloat = 136
    private static let gridSpacing: CGFloat = 10
    private static let horizontalPadding: CGFloat = 32
    private static let minPopoverWidth: CGFloat = 300
}

private enum PopoverGridItem: Identifiable {
    case provider(ProviderID, titleOverride: String?)
    case openCodeBackend(OpenCodeBackendUsage)

    var id: String {
        switch self {
        case .provider(let providerID, _):
            providerID.rawValue
        case .openCodeBackend(let backend):
            "opencode-backend-\(backend.providerKey)"
        }
    }
}

private struct ProviderCard: View {
    let providerID: ProviderID
    var titleOverride: String? = nil
    let snapshot: UsageSnapshot?
    let auth: AuthStatus
    let error: String?
    let trackingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderIconView(providerID: providerID, size: 22)
                Text(titleOverride ?? providerID.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)

            statusContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: Self.cardMinHeight, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var statusContent: some View {
        if let error {
            Text(error)
                .font(.caption2)
                .foregroundStyle(QuotaTheme.critical)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        } else if !trackingEnabled || isSignedOut {
            VStack(alignment: .leading, spacing: 2) {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Enable in Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if let snapshot {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshot.windows.prefix(2)) { window in
                    CompactMeter(window: window)
                }
            }
        } else {
            Text("No data yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var isSignedOut: Bool {
        if case .signedOut = auth { return true }
        return false
    }

    private static let cardMinHeight: CGFloat = 132
}

/// Spend for a BYOK backend used inside OpenCode (e.g. OpenRouter).
private struct OpenCodeBackendCard: View {
    let backend: OpenCodeBackendUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                backendGlyph
                Text(backend.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                CompactMeter(
                    window: UsageWindow(
                        kind: .weekly,
                        used: backend.weeklyUSD,
                        limit: 0,
                        unit: .credits,
                        resetsAt: Date().addingTimeInterval(7 * 24 * 3600)
                    )
                )
                CompactMeter(
                    window: UsageWindow(
                        kind: .monthly,
                        used: backend.monthlyUSD,
                        limit: 0,
                        unit: .credits,
                        resetsAt: Date().addingTimeInterval(30 * 24 * 3600)
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(backend.displayName) via OpenCode")
    }

    private var backendGlyph: some View {
        Text(letter)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 22 * 0.22, style: .continuous)
                    .fill(Color.black.opacity(0.88))
            )
            .accessibilityHidden(true)
    }

    private var letter: String {
        let trimmed = backend.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

private struct CompactMeter: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(valueLabel)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(meterColor)
                    .lineLimit(1)
            }
            ProgressView(value: window.limit > 0 ? window.utilization : 0)
                .tint(meterColor)
        }
    }

    private var valueLabel: String {
        if window.unit == .credits {
            if window.limit <= 0 {
                return String(format: "$%.2f", window.used)
            }
            if window.used != floor(window.used) || window.limit != floor(window.limit) {
                return String(format: "$%.2f/$%.0f", window.used, window.limit)
            }
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
