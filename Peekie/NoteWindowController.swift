import AppKit

@MainActor
final class NoteWindowController: NSObject, NSWindowDelegate {
    static let shared = NoteWindowController()

    private(set) var windows: [NoteWindow] = []
    private let cascadeOffset: CGFloat = 28

    private var closedNotes: [ClosedNote] = []
    private let maxClosedNotes = 10

    private var lastKeepOnTop = UserDefaults.standard.bool(forKey: PrefKey.keepNotesOnTop)
    private var lastSaveNotes = UserDefaults.standard.bool(forKey: PrefKey.saveNotes)
    private var saveWork: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var isTerminating = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appResignedActive() }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        }
    }

    private func settingsChanged() {
        let keepOnTop = UserDefaults.standard.bool(forKey: PrefKey.keepNotesOnTop)
        if keepOnTop != lastKeepOnTop {
            lastKeepOnTop = keepOnTop
            windows.forEach { $0.setKeepOnTop(keepOnTop) }
        }

        let saveNotes = UserDefaults.standard.bool(forKey: PrefKey.saveNotes)
        if saveNotes != lastSaveNotes {
            lastSaveNotes = saveNotes
            if saveNotes {
                windows.forEach { saveNow($0) }
            } else {
                NoteStore.shared.deleteAll()
            }
        }
    }

    func newNote(text: String? = nil) {
        show(NoteWindow(content: text.map { NSAttributedString(string: $0) }))
    }

    func reopenLastClosedNote() {
        guard let note = closedNotes.popLast() else { return }
        let window = NoteWindow(content: note.content, zoom: note.zoom)
        window.setFrame(note.frame, display: false)
        show(window, position: false)
    }

    func restoreSavedNotes() {
        guard NoteStore.shared.isEnabled else { return }
        for (meta, content) in NoteStore.shared.loadAll() {
            let window = NoteWindow(content: content, zoom: CGFloat(meta.zoom), id: meta.id, imageWidths: meta.imageWidths)
            if let rect = meta.rect, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                window.setFrame(rect, display: false)
                register(window)
            } else {
                register(window, cascade: true)
            }
            if meta.pinned { window.setKeepOnTop(true) }

            window.orderFrontRegardless()
        }
    }

    private func show(_ window: NoteWindow, position: Bool = true) {
        register(window, cascade: position)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        scheduleSave(window)
    }

    private func register(_ window: NoteWindow, cascade: Bool = false) {
        window.delegate = self
        if cascade {
            if let last = windows.last {
                window.setFrameTopLeftPoint(NSPoint(x: last.frame.minX + cascadeOffset, y: last.frame.maxY - cascadeOffset))
            } else {
                window.center()
            }
        }
        window.model.onChange = { [weak self, weak window] in
            guard let window else { return }
            self?.scheduleSave(window)
        }
        windows.append(window)
    }

    func toggleAllNotes() {
        let visible = windows.filter(\.isVisible)
        if !visible.isEmpty {
            visible.forEach { $0.orderOut(nil) }
        } else if windows.contains(where: { !$0.isMiniaturized }) {
            showAllNotes()
        } else {
            newNote()
        }
    }

    func showAllNotes() {
        NSApp.activate()
        for window in windows where !window.isMiniaturized {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var pendingClickAway: DispatchWorkItem?

    private func appResignedActive() {
        let mode = ClickAwayMode.stored
        guard mode != .keep else { return }
        pendingClickAway?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, !NSApp.isActive else { return }

            let targets = self.windows.filter { $0.isVisible && !$0.keepsOnTop }
            switch mode {
            case .fade:
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
                    targets.forEach { $0.animator().alphaValue = 0.35 }
                }
            case .hide:
                targets.forEach { $0.orderOut(nil) }
            case .keep:
                break
            }
        }
        pendingClickAway = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func appBecameActive() {
        pendingClickAway?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            windows.filter { $0.isVisible && $0.alphaValue < 1 }.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private func scheduleSave(_ window: NoteWindow) {
        guard NoteStore.shared.isEnabled else { return }
        let key = ObjectIdentifier(window)
        saveWork[key]?.cancel()
        let work = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else { return }
            self.saveNow(window)
        }
        saveWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func saveNow(_ window: NoteWindow) {
        guard NoteStore.shared.isEnabled, let textView = window.model.textView else { return }
        saveWork[ObjectIdentifier(window)]?.cancel()
        NoteStore.shared.save(
            id: window.model.id,
            content: textView.attributedString(),
            frame: window.frame,
            zoom: Double(textView.zoomDelta),
            pinned: window.keepsOnTop,
            imageWidths: textView.imageWidths()
        )
    }

    func prepareForTermination() {
        isTerminating = true
        windows.forEach { saveNow($0) }
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NoteWindow { scheduleSave(window) }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NoteWindow { scheduleSave(window) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NoteWindow else { return }
        windows.removeAll { $0 === window }
        saveWork[ObjectIdentifier(window)]?.cancel()
        saveWork[ObjectIdentifier(window)] = nil

        if !isTerminating { NoteStore.shared.delete(id: window.model.id) }

        if let closed = window.model.snapshot(frame: window.frame) {
            closedNotes.append(closed)
            if closedNotes.count > maxClosedNotes { closedNotes.removeFirst() }
        }
    }
}
