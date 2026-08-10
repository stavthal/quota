import AppKit
import Combine
import QuotaCore
import SwiftUI

/// Owns Headroom's single menu-bar item and its transient popover.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let session: AppSession
    private var sessionObservation: AnyCancellable?

    init(session: AppSession, notifications: NotificationService) {
        self.session = session
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(session: session, notifications: notifications)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusItem()
        sessionObservation = session.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                await Task.yield()
                self?.updateStatusItem()
            }
        }
    }

    @objc private func handleStatusItemClick() {
        guard let button = statusItem.button else { return }

        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            popover.performClose(nil)
            showContextMenu(event: event, from: button)
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu(event: NSEvent, from button: NSStatusBarButton) {
        let menu = NSMenu()
        let stopItem = NSMenuItem(
            title: "Stop Using Headroom",
            action: #selector(stopUsingHeadroom),
            keyEquivalent: ""
        )
        stopItem.target = self
        menu.addItem(stopItem)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func stopUsingHeadroom() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        button.subviews.filter { $0.identifier == Self.contentIdentifier }.forEach {
            $0.removeFromSuperview()
        }
        button.image = nil
        button.title = ""

        let content = PassthroughStackView()
        content.identifier = Self.contentIdentifier
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(severityIcon())

        let groups = MenuBarStatusFormatter.statusGroups(
            pins: session.preferences.orderedMenuBarPins,
            snapshots: session.snapshots
        )
        for group in groups {
            content.addArrangedSubview(providerGroup(group))
        }

        let contentSize = content.fittingSize
        statusItem.length = max(24, ceil(contentSize.width) + 8)

        button.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            content.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            content.widthAnchor.constraint(equalToConstant: ceil(contentSize.width)),
        ])

        button.toolTip = accessibilityLabel(groups: groups)
        button.setAccessibilityLabel(button.toolTip)
    }

    private func severityIcon() -> NSImageView {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(
            systemSymbolName: QuotaTheme.symbol(for: session.aggregateSeverity),
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true

        let view = NSImageView(image: image ?? NSImage())
        view.imageScaling = .scaleProportionallyDown
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 16),
            view.heightAnchor.constraint(equalToConstant: 18),
        ])
        return view
    }

    private func providerGroup(_ group: MenuBarStatusGroup) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.addArrangedSubview(providerIcon(group.providerID))

        let label = NSTextField(labelWithString: group.values.joined(separator: " · "))
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(label)
        return stack
    }

    private func providerIcon(_ providerID: ProviderID) -> NSView {
        let plate = NSView()
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        plate.layer?.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            plate.widthAnchor.constraint(equalToConstant: 16),
            plate.heightAnchor.constraint(equalToConstant: 16),
        ])

        let image: NSImage?
        if providerID == .claude {
            image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        } else {
            image = NSImage(named: providerID.assetIconName)
        }
        guard let image else { return plate }
        image.isTemplate = providerID.usesWhiteTintedIcon
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = providerID.usesWhiteTintedIcon ? .white : nil
        imageView.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 2.5),
            imageView.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -2.5),
            imageView.topAnchor.constraint(equalTo: plate.topAnchor, constant: 2.5),
            imageView.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -2.5),
        ])
        return plate
    }

    private func accessibilityLabel(groups: [MenuBarStatusGroup]) -> String {
        let values = groups.map { group in
            "\(group.providerID.displayName) \(group.values.joined(separator: ", "))"
        }
        let suffix = values.isEmpty ? "" : ", " + values.joined(separator: ", ")
        return "Headroom \(session.aggregateSeverity.rawValue)\(suffix)"
    }

    private static let contentIdentifier = NSUserInterfaceItemIdentifier("HeadroomStatusContent")
}

/// Lets the status-item button receive clicks from the custom visual content.
private final class PassthroughStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
