import AppKit

let suite = CommandLine.arguments.dropFirst().first ?? "logic"

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApplication.shared.setActivationPolicy(.accessory)
    UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
    PrefDefault.register()

    if suite == "logic" || suite == "all" { runLogicTests() }
    if suite == "editor" || suite == "all" { runEditorTests() }
    if suite == "window" || suite == "all" { runWindowTests() }
}

let summary = failures == 0 ? "\nAll tests passed\n" : "\n\(failures) test(s) failed\n"
FileHandle.standardError.write(summary.data(using: .utf8)!)
exit(failures == 0 ? 0 : 1)
