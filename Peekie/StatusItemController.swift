import AppKit

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?

    func update() {
        let wanted = UserDefaults.standard.bool(forKey: PrefKey.showMenuBarIcon)
        if wanted, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = MenuBarIcon.image()
            item.button?.toolTip = "Peekie"
            item.menu = makeMenu()
            statusItem = item
        } else if !wanted, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("New Note", #selector(newNote)))
        menu.addItem(item("Show or Hide Notes", #selector(toggleNotes)))
        menu.addItem(item("Reopen Closed Note", #selector(reopenClosedNote)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Peekie", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func newNote() { NoteWindowController.shared.newNote() }
    @objc private func toggleNotes() { NoteWindowController.shared.toggleAllNotes() }
    @objc private func reopenClosedNote() { NoteWindowController.shared.reopenLastClosedNote() }
    @objc private func showSettings() { SettingsWindowController.shared.show() }
}
