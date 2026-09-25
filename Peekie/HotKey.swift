import Carbon.HIToolbox
import Foundation

final class HotKey {
    static let shared = HotKey()

    var handlers: [UInt32: () -> Void] = [:]

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    @discardableResult
    func register(_ action: HotKeyAction) -> Bool {
        unregister(action)
        installHandlerIfNeeded()
        let id = UInt32(action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(action.storedCode), UInt32(action.storedModifiers),
            EventHotKeyID(signature: OSType(0x5045_454B), id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        return true
    }

    func registerAll() {
        HotKeyAction.allCases.forEach { register($0) }
    }

    func unregister(_ action: HotKeyAction) {
        if let ref = refs.removeValue(forKey: UInt32(action.rawValue)) {
            UnregisterEventHotKey(ref)
        }
    }

    func unregisterAll() {
        HotKeyAction.allCases.forEach { unregister($0) }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            HotKey.shared.handlers[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
