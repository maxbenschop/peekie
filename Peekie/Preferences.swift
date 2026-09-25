import AppKit
import Carbon.HIToolbox
import Foundation

enum PrefKey {
    static let backgroundOpacity = "backgroundOpacity"
    static let blurRadius = "blurRadius"
    static let appearanceMode = "appearanceMode"
    static let keepNotesOnTop = "keepNotesOnTop"
    static let saveNotes = "saveNotes"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let clickAwayMode = "clickAwayMode"
    static let monospacedFont = "monospacedFont"
    static let fontSize = "fontSize"
    static let didSetUpLoginItem = "didSetUpLoginItem"
}

enum PrefDefault {
    static let fontSize = 13.0
    static let backgroundOpacity = 0.6

    static let blurRadius = 12.0

    static func register() {
        UserDefaults.standard.register(defaults: [
            PrefKey.backgroundOpacity: backgroundOpacity,
            PrefKey.blurRadius: blurRadius,
            PrefKey.appearanceMode: AppearanceMode.dark.rawValue,
            PrefKey.keepNotesOnTop: false,
            PrefKey.saveNotes: false,
            PrefKey.showMenuBarIcon: false,
            PrefKey.clickAwayMode: ClickAwayMode.keep.rawValue,
            PrefKey.monospacedFont: false,
            PrefKey.fontSize: fontSize,
        ].merging(MenuShortcut.allCases.flatMap { shortcut in
            [
                shortcut.keyPref: shortcut.defaultKey,
                shortcut.modifiersPref: Int(shortcut.defaultModifiers.rawValue),
            ] as [String: Any]
        }) { current, _ in current }
        .merging(HotKeyAction.allCases.flatMap { action in
            [
                action.codeKey: action.defaultCode,
                action.modifiersKey: action.defaultModifiers,
                action.labelKey: action.defaultLabel,
            ] as [String: Any]
        }) { current, _ in current })
    }
}

enum HotKeyAction: Int, CaseIterable {
    case newNote = 1
    case captureSelection = 2
    case toggleNotes = 3

    private var prefix: String {
        switch self {
        case .newNote: return "hotKey"
        case .captureSelection: return "captureHotKey"
        case .toggleNotes: return "toggleHotKey"
        }
    }

    var codeKey: String { prefix + "Code" }
    var modifiersKey: String { prefix + "Modifiers" }
    var labelKey: String { prefix + "Label" }

    var defaultCode: Int { self == .toggleNotes ? Int(kVK_ANSI_N) : Int(kVK_Space) }
    var defaultModifiers: Int {
        switch self {
        case .newNote: return optionKey
        case .captureSelection: return optionKey | shiftKey
        case .toggleNotes: return controlKey | optionKey
        }
    }
    var defaultLabel: String { self == .toggleNotes ? "N" : "Space" }

    var storedCode: Int { UserDefaults.standard.integer(forKey: codeKey) }
    var storedModifiers: Int { UserDefaults.standard.integer(forKey: modifiersKey) }
}

enum MenuShortcut: String, CaseIterable {
    case keepOnTop
    case reopenClosedNote
    case copyAllAndClose

    var keyPref: String { rawValue + "Key" }
    var modifiersPref: String { rawValue + "Modifiers" }

    var title: String {
        switch self {
        case .keepOnTop: return "Keep on top"
        case .reopenClosedNote: return "Reopen closed note"
        case .copyAllAndClose: return "Copy all and close"
        }
    }

    var defaultKey: String {
        switch self {
        case .keepOnTop, .reopenClosedNote: return "t"
        case .copyAllAndClose: return "c"
        }
    }

    var defaultModifiers: NSEvent.ModifierFlags {
        switch self {
        case .keepOnTop: return [.command, .option]
        case .reopenClosedNote, .copyAllAndClose: return [.command, .shift]
        }
    }

    var key: String { UserDefaults.standard.string(forKey: keyPref) ?? defaultKey }
    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: modifiersPref)))
            .intersection([.command, .option, .control, .shift])
    }

    var display: String { Self.display(key: key, modifiers: modifiers) }

    static func display(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }

    static func resetAll() {
        let defaults = UserDefaults.standard
        for shortcut in allCases {
            defaults.removeObject(forKey: shortcut.keyPref)
            defaults.removeObject(forKey: shortcut.modifiersPref)
        }
        for action in HotKeyAction.allCases {
            defaults.removeObject(forKey: action.codeKey)
            defaults.removeObject(forKey: action.modifiersKey)
            defaults.removeObject(forKey: action.labelKey)
        }
    }

    @MainActor
    static func conflict(key: String, modifiers: NSEvent.ModifierFlags, excluding shortcut: MenuShortcut) -> NSMenuItem? {
        func search(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.identifier?.rawValue != shortcut.rawValue,
                   !item.keyEquivalent.isEmpty,
                   item.keyEquivalent.lowercased() == key,
                   item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]) == modifiers {
                    return item
                }
                if let submenu = item.submenu, let found = search(submenu) { return found }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(search)
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static var stored: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.appearanceMode) ?? "") ?? .dark
    }
}

enum ClickAwayMode: String, CaseIterable, Identifiable {
    case keep, fade, hide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: return "Stay visible"
        case .fade: return "Fade"
        case .hide: return "Hide"
        }
    }

    static var stored: ClickAwayMode {
        ClickAwayMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.clickAwayMode) ?? "") ?? .keep
    }
}
