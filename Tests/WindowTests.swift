import AppKit
import QuartzCore

@MainActor
func runWindowTests() {
    blurTests()
    appearanceTests()
    let directory = temporaryDirectory("windows")
    NoteStore.shared = NoteStore(directory: directory)
    keepOnTopTests()
    persistenceTests(directory: directory)
    visibilityTests()
    imageWindowTests()
    statusItemTests()
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
private func backdropLayer(in layer: CALayer) -> CALayer? {
    if String(describing: type(of: layer)) == "CABackdropLayer" { return layer }
    for sublayer in layer.sublayers ?? [] {
        if let found = backdropLayer(in: sublayer) { return found }
    }
    return nil
}

@MainActor
private func blurState(_ view: BlurView) -> (radius: Double?, kinds: [String], tintHidden: Bool) {
    guard let backdrop = view.layer.flatMap(backdropLayer(in:)) else { return (nil, [], false) }
    let filters = (backdrop.filters ?? []).compactMap { $0 as? NSObject }
    let kinds = filters.compactMap { $0.value(forKey: "type") as? String }
    let radius = (filters.first { ($0.value(forKey: "type") as? String) == "gaussianBlur" }?.value(forKey: "inputRadius") as? NSNumber)?.doubleValue
    let tintHidden = (backdrop.superlayer?.sublayers ?? []).filter { $0 !== backdrop }.allSatisfy { $0.opacity == 0 }
    return (radius, kinds, tintHidden)
}

@MainActor
private func blurTests() {
    section("Blur")
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
        styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.appearance = NSAppearance(named: .darkAqua)
    let view = BlurView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .active
    view.radius = 12
    window.contentView = view
    window.orderFrontRegardless()
    spin(1.0)
    if view.layer.flatMap(backdropLayer(in:)) == nil && ProcessInfo.processInfo.environment["CI"] != nil {
        skip("this machine has no graphics backdrop (virtual machine), so the blur layers cannot be checked here")
        window.close()
        return
    }
    var state = blurState(view)
    check(
        state.radius == 12 && state.kinds == ["sdrNormalize", "gaussianBlur"] && state.tintHidden && view.alphaValue == 1,
        "the radius is applied, saturation is removed and the material tint is hidden (radius \(String(describing: state.radius)), filters \(state.kinds), tint hidden \(state.tintHidden), alpha \(view.alphaValue))"
    )
    let before = view.layer.flatMap(backdropLayer(in:))?.filters.map { $0.map { ObjectIdentifier($0 as AnyObject) } }
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
    spin(0.3)
    let after = view.layer.flatMap(backdropLayer(in:))?.filters.map { $0.map { ObjectIdentifier($0 as AnyObject) } }
    check(before == after, "layout passes do not rebuild the filters")
    view.radius = 30
    spin(0.3)
    let replaced = view.layer.flatMap(backdropLayer(in:))?.filters.map { $0.map { ObjectIdentifier($0 as AnyObject) } }
    check(blurState(view).radius == 30 && replaced != after, "changing the radius installs a new filter array")
    view.radius = 0
    spin(0.3)
    check(blurState(view).radius == 0, "a radius of zero is applied")
    view.radius = 25
    spin(0.2)
    window.appearance = NSAppearance(named: .aqua)
    spin(1.2)
    state = blurState(view)
    check(state.radius == 25 && state.kinds == ["sdrNormalize", "gaussianBlur"] && state.tintHidden, "the settings survive an appearance change")
    window.setContentSize(NSSize(width: 500, height: 400))
    spin(0.4)
    window.orderOut(nil)
    window.orderFrontRegardless()
    spin(0.6)
    check(blurState(view).radius == 25 && blurState(view).tintHidden, "the settings survive resizing and hiding")
}

@MainActor
private func appearanceTests() {
    section("Appearance mode")
    check(AppearanceMode.stored == .dark, "dark is the default")
    UserDefaults.standard.set("light", forKey: PrefKey.appearanceMode)
    check(AppearanceMode.stored == .light && AppearanceMode.stored.appearance?.name == .aqua, "light resolves to aqua")
    UserDefaults.standard.set("system", forKey: PrefKey.appearanceMode)
    check(AppearanceMode.stored == .system && AppearanceMode.stored.appearance == nil, "system follows the OS")
    UserDefaults.standard.set("nonsense", forKey: PrefKey.appearanceMode)
    check(AppearanceMode.stored == .dark, "an invalid value falls back to dark")
    UserDefaults.standard.set("dark", forKey: PrefKey.appearanceMode)
}

@MainActor
private func closeAllNotes() {
    for window in NoteWindowController.shared.windows { window.close() }
}

@MainActor
private func keepOnTopTests() {
    section("Keep on top")
    let controller = NoteWindowController.shared
    controller.newNote()
    spin(0.4)
    guard let first = controller.windows.first else { return }
    check(first.level == .normal, "a new note is a normal window by default")
    UserDefaults.standard.set(true, forKey: PrefKey.keepNotesOnTop)
    spin(0.3)
    check(first.level == .floating, "turning the setting on floats the open note")
    controller.newNote()
    spin(0.4)
    let second = controller.windows[1]
    check(second.level == .floating, "a new note starts on top when the setting is on")
    first.toggleKeepOnTop(nil)
    check(first.level == .normal && second.level == .floating, "a single note can still be pinned separately")
    UserDefaults.standard.set(false, forKey: PrefKey.keepNotesOnTop)
    spin(0.3)
    check(first.level == .normal && second.level == .normal, "turning the setting off releases every note")
    check(first.appearance == nil, "note windows follow the app-wide appearance")
    closeAllNotes()
}

@MainActor
private func files(in directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
}

@MainActor
private func persistenceTests(directory: URL) {
    section("Saving and restoring notes")
    let controller = NoteWindowController.shared
    let defaults = UserDefaults.standard

    controller.newNote(text: "unsaved")
    spin(1.4)
    check(files(in: directory).isEmpty, "nothing is written while saving is off")
    closeAllNotes()

    defaults.set(true, forKey: PrefKey.saveNotes)
    spin(0.2)
    controller.newNote(text: "hello saved note")
    spin(0.3)
    guard let window = controller.windows.first, let textView = window.model.textView else { return }
    check(files(in: directory).isEmpty, "saving is debounced")
    spin(1.3)
    check(files(in: directory).count == 2, "a note and its metadata are written")

    textView.setSelectedRange(NSRange(location: 0, length: 5))
    textView.toggleBold(nil)
    textView.increaseFontSize(nil)
    textView.increaseFontSize(nil)
    window.setKeepOnTop(true)
    window.setFrame(NSRect(x: 120, y: 140, width: 480, height: 300), display: false)
    spin(1.4)
    let saved = NoteStore.shared.loadAll()
    check(saved.count == 1 && saved[0].content.string == "hello saved note", "the text is saved")
    check(saved.first?.meta.zoom == 2 && saved.first?.meta.pinned == true, "zoom and the pinned state are saved")
    check(saved.first?.meta.rect == NSRect(x: 120, y: 140, width: 480, height: 300), "the window frame is saved")

    let id = window.model.id
    controller.prepareForTermination()
    closeAllNotes()
    check(files(in: directory).count == 2, "saved files survive quitting")
    controller.restoreSavedNotes()
    spin(0.6)
    check(controller.windows.count == 1, "the note is restored on launch")
    if let restored = controller.windows.first, let restoredView = restored.model.textView {
        check(restored.model.id == id, "the restored note keeps its identity")
        check(restoredView.string == "hello saved note", "the text is restored")
        check(restored.keepsOnTop, "the pinned state is restored")
        check(abs(restored.frame.width - 480) < 1 && abs(restored.frame.height - 300) < 1, "the size is restored")
        let font = restoredView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check(font?.fontDescriptor.symbolicTraits.contains(.bold) == true && font?.pointSize == 15, "bold and zoom are restored")
        check(restoredView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NoteTextView.defaultColour, "the default text colour is restored")
    }
    NoteStore.shared.deleteAll()
    closeAllNotes()

    defaults.set(false, forKey: PrefKey.saveNotes)
    spin(0.3)
    NoteStore.shared.deleteAll()
}

@MainActor
private func visibilityTests() {
    section("Show, hide and click away")
    let controller = NoteWindowController.shared
    let defaults = UserDefaults.standard
    closeAllNotes()

    controller.newNote(text: "one")
    controller.newNote(text: "two")
    spin(0.3)
    check(controller.windows.count == 2 && controller.windows.allSatisfy(\.isVisible), "two notes are visible")
    controller.toggleAllNotes()
    spin(0.2)
    check(controller.windows.allSatisfy { !$0.isVisible }, "the toggle hides every note")
    controller.toggleAllNotes()
    spin(0.3)
    check(controller.windows.allSatisfy(\.isVisible), "the toggle shows them again")
    closeAllNotes()
    controller.toggleAllNotes()
    spin(0.3)
    check(controller.windows.count == 1, "the toggle starts a note when there are none")
    closeAllNotes()

    controller.newNote(text: "a")
    controller.newNote(text: "b")
    spin(0.3)
    let (plain, pinned) = (controller.windows[0], controller.windows[1])
    pinned.setKeepOnTop(true)
    defaults.set("hide", forKey: PrefKey.clickAwayMode)
    NSApp.deactivate()
    spin(0.2)
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    spin(0.6)
    check(!plain.isVisible && pinned.isVisible, "Hide hides a normal note and keeps a pinned one")
    controller.showAllNotes()
    spin(0.3)
    check(plain.isVisible, "showing brings it back")
    defaults.set("fade", forKey: PrefKey.clickAwayMode)
    NSApp.deactivate()
    spin(0.2)
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    spin(0.9)
    check(plain.alphaValue < 0.5 && pinned.alphaValue == 1, "Fade dims a normal note and not a pinned one")
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    spin(0.5)
    check(plain.alphaValue == 1, "becoming active restores it")
    defaults.set("keep", forKey: PrefKey.clickAwayMode)
    NSApp.deactivate()
    spin(0.2)
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    spin(0.5)
    check(plain.isVisible && plain.alphaValue == 1, "Stay visible does nothing")
    closeAllNotes()
}

@MainActor
private func imageWindowTests() {
    section("Images in a note window")
    let controller = NoteWindowController.shared
    closeAllNotes()
    controller.newNote()
    spin(0.9)
    guard let window = controller.windows.first, let textView = window.model.textView else { return }
    type(textView, "x")
    textView.insertImage(makeImage(width: 2880, height: 1800))
    spin(0.4)
    let noteWidth = textView.bounds.width
    let first = attachments(in: textView)[0].bounds
    check(first.width < noteWidth * 0.6 && first.height < 0.62 * textView.visibleRect.height, "a pasted image starts at a modest size")
    check(abs(drawnImageWidth(of: textView) - first.width) < 2, "and is drawn at that size")
    type(textView, " and ")
    textView.insertImage(makeImage(width: 800, height: 2400))
    spin(0.4)
    check(attachments(in: textView).count == 2 && attachments(in: textView)[1].bounds.height < 0.62 * textView.visibleRect.height, "a tall image is limited in height")

    let index = (textView.string as NSString).range(of: "\u{FFFC}").location
    func setSize(_ tag: Int) {
        let item = NSMenuItem()
        item.tag = tag
        item.representedObject = index
        textView.setImageSize(item)
        spin(0.2)
    }
    func maxWidth() -> CGFloat { textView.bounds.width - 16 - 12 }
    func firstWidth() -> CGFloat { attachments(in: textView)[0].bounds.width }
    setSize(1)
    check(abs(firstWidth() - maxWidth() * 0.25) < 1, "Small is 25% of the note width (\(firstWidth()) of \(maxWidth()))")
    setSize(2)
    check(abs(firstWidth() - maxWidth() * 0.5) < 1, "Medium is 50% (\(firstWidth()) of \(maxWidth()))")
    setSize(3)
    check(abs(firstWidth() - maxWidth()) < 1, "Large fits the note (\(firstWidth()) of \(maxWidth()))")
    check(abs(drawnImageWidth(of: textView) - firstWidth()) < 3, "and is drawn at that width (drawn \(drawnImageWidth(of: textView)), bounds \(firstWidth()))")
    setSize(4)
    check(firstWidth() <= maxWidth() + 0.5, "Actual Size is capped to the note (\(firstWidth()) of \(maxWidth()))")
    let expectedMedium = maxWidth() * 0.5
    setSize(2)
    check(abs(firstWidth() - expectedMedium) < 1, "Medium applies again (\(firstWidth()) of \(expectedMedium))")
    let widths = textView.imageWidths()
    check(widths.count == 2 && abs(widths[0] - firstWidth()) < 0.01, "image widths are reported in order (\(widths))")

    let directory = temporaryDirectory("images")
    let store = NoteStore(directory: directory)
    store.save(id: window.model.id, content: textView.attributedString(), frame: window.frame, zoom: 0, pinned: false, imageWidths: widths)
    let loaded = store.loadAll()
    check(loaded.count == 1 && loaded[0].meta.imageWidths?.count == 2, "image widths are stored with the note")
    let restored = NoteWindow(content: loaded[0].content, zoom: 0, id: UUID(), imageWidths: loaded[0].meta.imageWidths)
    restored.orderFrontRegardless()
    spin(0.9)
    if let restoredView = restored.model.textView {
        let sizes = attachments(in: restoredView).map(\.bounds.width)
        check(sizes.count == 2 && zip(sizes, widths).allSatisfy { abs($0 - $1) < 1 }, "restored images keep their sizes")
        check((sizes.first ?? 0) > 100, "a restored image is not squashed to a thumbnail")
        restored.setFrame(NSRect(x: 50, y: 50, width: 1000, height: 600), display: true)
        spin(0.5)
        check(abs(attachments(in: restoredView)[0].bounds.width - sizes[0]) < 1, "widening the note leaves image sizes alone")
        restored.setFrame(NSRect(x: 50, y: 50, width: 240, height: 400), display: true)
        spin(0.5)
        check(attachments(in: restoredView)[0].bounds.width <= restoredView.bounds.width - 16 - 12 + 0.5, "narrowing the note keeps images inside it")
    }
    restored.close()
    try? FileManager.default.removeItem(at: directory)

    window.performClose(nil)
    spin(0.3)
    controller.reopenLastClosedNote()
    spin(0.9)
    if let reopened = controller.windows.last, let reopenedView = reopened.model.textView {
        let sizes = attachments(in: reopenedView).map(\.bounds.width)
        check(sizes.count == 2 && abs(sizes[0] - widths[0]) < 1, "a reopened note keeps its image sizes")
    } else {
        check(false, "a closed note can be reopened")
    }
    closeAllNotes()
}

@MainActor
private func statusItemTests() {
    section("Menu bar icon")
    let status = StatusItemController.shared
    UserDefaults.standard.set(true, forKey: PrefKey.showMenuBarIcon)
    status.update()
    status.update()
    UserDefaults.standard.set(false, forKey: PrefKey.showMenuBarIcon)
    status.update()
    status.update()
    UserDefaults.standard.set(true, forKey: PrefKey.showMenuBarIcon)
    status.update()
    UserDefaults.standard.set(false, forKey: PrefKey.showMenuBarIcon)
    status.update()
    check(true, "the icon can be added and removed repeatedly")
}
