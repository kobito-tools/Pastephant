import Carbon
import Foundation

/// どのアプリを使っていても効くショートカット。Carbon の RegisterEventHotKey を使うので、アクセシビリティの許可はいらない。
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    private var reference: EventHotKeyRef?
    private let id: UInt32

    /// keyCode は kVK_ANSI_V など、modifiers は cmdKey | optionKey など。
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.installEventHandler()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x5073_5068), id: id)  // 'PsPh'
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &reference) == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        Self.handlers[id] = nil
    }

    private static func installEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if let handler = HotKey.handlers[hotKeyID.id] { DispatchQueue.main.async(execute: handler) }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
