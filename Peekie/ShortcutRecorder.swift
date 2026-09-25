import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: View {
    let action: HotKeyAction

    @AppStorage private var keyCode: Int
    @AppStorage private var modifiers: Int
    @AppStorage private var label: String

    @State private var recording = false
    @State private var monitor: Any?
    @State private var failed = false

    init(action: HotKeyAction) {
        self.action = action
        _keyCode = AppStorage(wrappedValue: action.defaultCode, action.codeKey)
        _modifiers = AppStorage(wrappedValue: action.defaultModifiers, action.modifiersKey)
        _label = AppStorage(wrappedValue: action.defaultLabel, action.labelKey)
    }

    var body: some View {
        HStack {
            if failed {
                Text("Shortcut unavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(recording ? "Type shortcut…" : Self.display(modifiers: modifiers, label: label)) {
                recording ? stopRecording() : startRecording()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("New note shortcut")
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        failed = false
        recording = true

        HotKey.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKey.shared.registerAll()
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let carbon = Self.carbonModifiers(event.modifierFlags)

        guard carbon & (cmdKey | optionKey | controlKey) != 0 else { return }

        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil

        let takenByOther = HotKeyAction.allCases.contains {
            $0 != action && $0.storedCode == Int(event.keyCode) && $0.storedModifiers == carbon
        }
        guard !takenByOther else {
            failed = true
            HotKey.shared.registerAll()
            return
        }

        let previous = (keyCode, modifiers, label)
        keyCode = Int(event.keyCode)
        modifiers = carbon
        label = Self.keyLabel(for: event)

        HotKey.shared.unregisterAll()
        if !HotKey.shared.register(action) {
            (keyCode, modifiers, label) = previous
            failed = true
        }
        HotKey.shared.registerAll()
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return result
    }

    static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            guard let chars = event.charactersIgnoringModifiers?.uppercased(),
                  let scalar = chars.unicodeScalars.first,
                  !(0xF700...0xF8FF).contains(scalar.value) else {
                return "Key \(event.keyCode)"
            }
            return chars
        }
    }

    static func display(modifiers: Int, label: String) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + label
    }
}

struct MenuShortcutRecorder: View {
    let shortcut: MenuShortcut

    @AppStorage private var key: String
    @AppStorage private var modifiers: Int

    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    init(shortcut: MenuShortcut) {
        self.shortcut = shortcut
        _key = AppStorage(wrappedValue: shortcut.defaultKey, shortcut.keyPref)
        _modifiers = AppStorage(wrappedValue: Int(shortcut.defaultModifiers.rawValue), shortcut.modifiersPref)
    }

    var body: some View {
        HStack {
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(recording ? "Type shortcut…" : MenuShortcut.display(key: key, modifiers: flags)) {
                recording ? stopRecording() : startRecording()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(shortcut.title)
        }
        .onDisappear { stopRecording() }
    }

    private var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(modifiers)).intersection([.command, .option, .control, .shift])
    }

    private func startRecording() {
        problem = nil
        recording = true

        HotKey.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKey.shared.registerAll()
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        guard !mods.isDisjoint(with: [.command, .option, .control]),
              let typed = event.charactersIgnoringModifiers?.lowercased(),
              typed.count == 1, let scalar = typed.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar),
              !(0xF700...0xF8FF).contains(scalar.value) else { return }

        if let taken = MenuShortcut.conflict(key: typed, modifiers: mods, excluding: shortcut) {
            problem = "Already used by \(taken.title)"
        } else {
            key = typed
            modifiers = Int(mods.rawValue)
            problem = nil
        }
        stopRecording()
    }
}
