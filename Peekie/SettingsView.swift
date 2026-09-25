import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @AppStorage(PrefKey.backgroundOpacity) private var backgroundOpacity = PrefDefault.backgroundOpacity
    @AppStorage(PrefKey.appearanceMode) private var appearanceMode = AppearanceMode.dark.rawValue
    @AppStorage(PrefKey.keepNotesOnTop) private var keepNotesOnTop = false
    @AppStorage(PrefKey.saveNotes) private var saveNotes = false
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = false
    @AppStorage(PrefKey.clickAwayMode) private var clickAwayMode = ClickAwayMode.keep.rawValue
    @AppStorage(PrefKey.monospacedFont) private var monospaced = false
    @AppStorage(PrefKey.fontSize) private var fontSize = PrefDefault.fontSize

    @AppStorage(PrefKey.blurRadius) private var blurRadius = PrefDefault.blurRadius

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            launchAtLogin = LoginItem.isEnabled
                            loginError = error.localizedDescription
                        }
                    }
                Toggle("Keep notes on top of other windows", isOn: $keepNotesOnTop)
                Toggle("Save notes between launches", isOn: $saveNotes)
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                if let loginError {
                    Text(loginError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("When I click away", selection: $clickAwayMode) {
                    ForEach(ClickAwayMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
            } header: {
                Text("Behaviour")
            } footer: {
                Text("Pinned notes always stay visible. Bring hidden notes back with the show or hide shortcut.")
            }

            Section {
                LabeledContent("New note (anywhere)") {
                    ShortcutRecorder(action: .newNote)
                }
                LabeledContent("Quick capture selection (anywhere)") {
                    ShortcutRecorder(action: .captureSelection)
                }
                LabeledContent("Show or hide all notes (anywhere)") {
                    ShortcutRecorder(action: .toggleNotes)
                }
                if !accessibilityTrusted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick capture copies your selection into a new note, which needs Accessibility access.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Accessibility Settings…") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                            accessibilityTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
                        }
                    }
                }
                ForEach(MenuShortcut.allCases, id: \.self) { shortcut in
                    LabeledContent(shortcut.title.prefix(1).uppercased() + shortcut.title.dropFirst()) {
                        MenuShortcutRecorder(shortcut: shortcut)
                    }
                }
                Button("Reset Shortcuts") {
                    MenuShortcut.resetAll()
                    HotKey.shared.registerAll()
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Shortcuts marked (anywhere) work from any app. The others work while a note is active.")
            }

            Section("Appearance") {
                Picker("Mode", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Background opacity") {
                    Slider(value: $backgroundOpacity, in: 0.1...1.0)
                        .frame(width: 180)
                }
                LabeledContent("Background blur") {
                    Slider(value: $blurRadius, in: 0...Double(BlurView.maxRadius))
                        .frame(width: 180)
                }
                Picker("Font", selection: $monospaced) {
                    Text("System").tag(false)
                    Text("Monospaced").tag(true)
                }
                Stepper("Font size: \(Int(fontSize)) pt", value: $fontSize, in: 10...24, step: 1)
            }

            Section {
                EmptyView()
            } footer: {
                Text(saveNotes
                     ? "Open notes are saved unencrypted in ~/Library/Application Support/Peekie and come back after a relaunch. Closing a note with ⌘W still discards it."
                     : "Notes are temporary. Closing a note with ⌘W discards it.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            accessibilityTrusted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Peekie Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
