import SwiftUI

final class NoteWindow: NSWindow {
    static let defaultSize = NSSize(width: 520, height: 340)
    static let minimumSize = NSSize(width: 240, height: 120)

    let model: NoteModel
    private let pinButton = NSButton()

    init(content: NSAttributedString? = nil, zoom: CGFloat = 0, id: UUID = UUID(), imageWidths: [Double]? = nil) {
        model = NoteModel(id: id)
        model.initialContent = content
        model.initialZoom = zoom
        model.initialImageWidths = imageWidths
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        isRestorable = false
        isReleasedWhenClosed = false

        contentMinSize = Self.minimumSize
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: NoteView(model: model))
        hosting.sizingOptions = []
        contentView = hosting

        level = UserDefaults.standard.bool(forKey: PrefKey.keepNotesOnTop) ? .floating : .normal
        addPinButton()
    }

    @objc func toggleKeepOnTop(_ sender: Any?) {
        setKeepOnTop(!keepsOnTop)
    }

    func setKeepOnTop(_ on: Bool) {
        level = on ? .floating : .normal
        updatePinButton()
        model.onChange?()
    }

    var keepsOnTop: Bool { level == .floating }

    private func addPinButton() {
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(toggleKeepOnTop(_:))
        pinButton.toolTip = "Keep on Top (\(MenuShortcut.keepOnTop.display))"
        pinButton.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        updatePinButton()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        container.addSubview(pinButton)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .trailing
        addTitlebarAccessoryViewController(accessory)
    }

    private func updatePinButton() {
        let symbol = keepsOnTop ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Keep on top")
        pinButton.contentTintColor = keepsOnTop ? .controlAccentColor : .secondaryLabelColor
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleKeepOnTop(_:)) {
            (item as? NSMenuItem)?.state = keepsOnTop ? .on : .off
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
