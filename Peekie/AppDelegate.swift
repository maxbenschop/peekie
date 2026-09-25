import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PrefDefault.register()
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = AppearanceMode.stored.appearance
        NSApp.mainMenu = makeMainMenu()

        HotKey.shared.handlers[UInt32(HotKeyAction.newNote.rawValue)] = {
            MainActor.assumeIsolated { NoteWindowController.shared.newNote() }
        }
        HotKey.shared.handlers[UInt32(HotKeyAction.captureSelection.rawValue)] = {
            MainActor.assumeIsolated { QuickCapture.run() }
        }
        HotKey.shared.handlers[UInt32(HotKeyAction.toggleNotes.rawValue)] = {
            MainActor.assumeIsolated { NoteWindowController.shared.toggleAllNotes() }
        }
        HotKey.shared.registerAll()

        applyMenuShortcuts()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyMenuShortcuts()
                self?.applyAppearance()
                StatusItemController.shared.update()
            }
        }

        enableLaunchAtLoginOnFirstRun()

        StatusItemController.shared.update()
        NoteWindowController.shared.restoreSavedNotes()

        if !Self.launchedAtLogin {
            SettingsWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteWindowController.shared.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func newNote() {
        NoteWindowController.shared.newNote()
    }

    @objc private func reopenClosedNote() {
        NoteWindowController.shared.reopenLastClosedNote()
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show()
    }

    private func applyAppearance() {
        let appearance = AppearanceMode.stored.appearance

        guard NSApp.appearance?.name != appearance?.name else { return }
        NSApp.appearance = appearance
    }

    private func applyMenuShortcuts() {
        func apply(to menu: NSMenu) {
            for item in menu.items {
                if let raw = item.identifier?.rawValue, let shortcut = MenuShortcut(rawValue: raw) {
                    let (key, modifiers) = (shortcut.key, shortcut.modifiers)
                    if item.keyEquivalent != key { item.keyEquivalent = key }
                    if item.keyEquivalentModifierMask != modifiers { item.keyEquivalentModifierMask = modifiers }
                }
                if let submenu = item.submenu { apply(to: submenu) }
            }
        }
        if let main = NSApp.mainMenu { apply(to: main) }
    }

    private func enableLaunchAtLoginOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: PrefKey.didSetUpLoginItem) else { return }
        defaults.set(true, forKey: PrefKey.didSetUpLoginItem)
        try? LoginItem.setEnabled(true)
    }

    private static var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isLoginEvent = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)

        return isLoginEvent || ProcessInfo.processInfo.systemUptime < 120
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        func add(_ menu: NSMenu, to main: NSMenu, title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }

        let name = ProcessInfo.processInfo.processName

        let appMenu = NSMenu(title: name)
        appMenu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main, title: name)

        let fileMenu = NSMenu(title: "File")
        let newNote = fileMenu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n")
        newNote.target = self
        let reopen = fileMenu.addItem(withTitle: "Reopen Closed Note", action: #selector(reopenClosedNote), keyEquivalent: "")
        reopen.identifier = NSUserInterfaceItemIdentifier(MenuShortcut.reopenClosedNote.rawValue)
        reopen.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save…", action: #selector(NoteTextView.saveNote(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Share…", action: #selector(NoteTextView.shareNote(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Print…", action: #selector(NoteTextView.printNote(_:)), keyEquivalent: "p")
        fileMenu.addItem(.separator())
        let copyClose = fileMenu.addItem(withTitle: "Copy All and Close", action: #selector(NoteTextView.copyAllAndClose(_:)), keyEquivalent: "")
        copyClose.identifier = NSUserInterfaceItemIdentifier(MenuShortcut.copyAllAndClose.rawValue)
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(fileMenu, to: main, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        let findMenu = NSMenu(title: "Find")
        for (title, key, action, modifiers) in [
            ("Find…", "f", NSTextFinder.Action.showFindInterface, NSEvent.ModifierFlags.command),
            ("Find Next", "g", .nextMatch, .command),
            ("Find Previous", "g", .previousMatch, [.command, .shift]),
        ] {
            let item = findMenu.addItem(withTitle: title, action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: key)
            item.tag = action.rawValue
            item.keyEquivalentModifierMask = modifiers
        }
        let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        find.submenu = findMenu
        editMenu.addItem(find)
        add(editMenu, to: main, title: "Edit")

        let formatMenu = MenuBuilder.formatMenu()
        add(formatMenu, to: main, title: "Format")

        let viewMenu = NSMenu(title: "View")
        MenuBuilder.zoomItems().forEach { viewMenu.addItem($0) }
        add(viewMenu, to: main, title: "View")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let keepOnTop = windowMenu.addItem(withTitle: "Keep on Top", action: #selector(NoteWindow.toggleKeepOnTop(_:)), keyEquivalent: "")
        keepOnTop.identifier = NSUserInterfaceItemIdentifier(MenuShortcut.keepOnTop.rawValue)
        add(windowMenu, to: main, title: "Window")
        NSApp.windowsMenu = windowMenu

        return main
    }
}
