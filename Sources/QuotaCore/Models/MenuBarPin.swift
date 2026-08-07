import Foundation

/// A usage window the user chose to show in the menu bar status item.
public struct MenuBarPin: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var providerID: ProviderID
    public var windowKind: UsageWindowKind

    public var id: String { "\(providerID.rawValue)-\(windowKind.rawValue)" }

    public init(providerID: ProviderID, windowKind: UsageWindowKind) {
        self.providerID = providerID
        self.windowKind = windowKind
    }
}
