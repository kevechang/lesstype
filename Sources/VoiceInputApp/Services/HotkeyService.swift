@preconcurrency import ApplicationServices
import AppKit
import Carbon
import Foundation

public enum HotkeyAction: Equatable, Sendable {
    case toggleOrdinary
    case toggleStructured
    case commitCurrent
    case discard
}

@MainActor
public final class HotkeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapContext: HotkeyEventTapContext?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var eventHandler: EventHandlerRef?
    private var registeredHotkeys: [EventHotKeyRef] = []
    private var activeSessionSpaceHotkey: EventHotKeyRef?
    private var activeSessionDiscardHotkey: EventHotKeyRef?
    private let parser = HotkeyEventParser()
    private let sessionActivity = HotkeySessionActivity()
    private let preferences: @MainActor () -> Preferences
    private let handler: @MainActor (HotkeyAction) -> Void
    public private(set) var isRunning = false
    public private(set) var lastStartFailed = false

    public init(
        preferences: @escaping @MainActor () -> Preferences = { .defaults },
        handler: @escaping @MainActor (HotkeyAction) -> Void
    ) {
        self.preferences = preferences
        self.handler = handler
    }

    public func start() {
        stop()
        lastStartFailed = false
        startCarbonHotkeys()

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let context = HotkeyEventTapContext(service: self, sessionActivity: sessionActivity)
        eventTapContext = context
        let unmanagedContext = Unmanaged.passUnretained(context).toOpaque()
        guard let newEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                guard let snapshot = HotkeyEventSnapshot(type: type, event: event) else {
                    return Unmanaged.passUnretained(event)
                }

                let context = Unmanaged<HotkeyEventTapContext>.fromOpaque(refcon).takeUnretainedValue()
                if context.sessionActivity.isActive {
                    if let action = context.sessionActivity.claim(snapshot.activeSessionAction(preferences: context.service.preferences())) {
                        Task { @MainActor in
                            context.service.handle(action)
                        }
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard snapshot.shouldRouteToParser else {
                    return Unmanaged.passUnretained(event)
                }

                Task { @MainActor in
                    context.service.handle(snapshot)
                }
                return snapshot.kind == .keyDown ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: unmanagedContext
        ) else {
            eventTapContext = nil
            lastStartFailed = true
            return
        }

        guard let newRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newEventTap, 0) else {
            CFMachPortInvalidate(newEventTap)
            eventTapContext = nil
            lastStartFailed = true
            return
        }

        eventTap = newEventTap
        runLoopSource = newRunLoopSource
        startKeyMonitors(context: context)
        CFRunLoopAddSource(CFRunLoopGetMain(), newRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newEventTap, enable: true)
        isRunning = !registeredHotkeys.isEmpty || eventTap != nil
    }

    public func stop() {
        unregisterActiveSessionHotkeys()
        unregisterCarbonHotkeys()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        localKeyMonitor = nil
        globalKeyMonitor = nil
        runLoopSource = nil
        eventTap = nil
        eventTapContext = nil
        isRunning = false
    }

    public func updateSessionActive(_ isActive: Bool) {
        sessionActivity.setActive(isActive)
        if isActive {
            registerActiveSessionSpaceHotkey()
            registerActiveSessionDiscardHotkey(preferences().resolvedDiscardHotkey)
        } else {
            unregisterActiveSessionHotkeys()
        }
    }

    private func startKeyMonitors(context: HotkeyEventTapContext) {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard let snapshot = HotkeyEventSnapshot(event: event),
                  let action = context.sessionActivity.claim(snapshot.activeSessionAction(preferences: context.service.preferences())) else {
                return event
            }
            Task { @MainActor in
                context.service.handle(action)
            }
            return nil
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard let snapshot = HotkeyEventSnapshot(event: event),
                  let action = context.sessionActivity.claim(snapshot.activeSessionAction(preferences: context.service.preferences())) else {
                return
            }
            Task { @MainActor in
                context.service.handle(action)
            }
        }
    }

    private func startCarbonHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard status == noErr else {
                    return status
                }

                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    service.handleCarbonHotkey(id: hotkeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            unmanagedSelf,
            &eventHandler
        )
        guard installStatus == noErr else {
            lastStartFailed = true
            return
        }

        let currentPreferences = preferences()
        registerCarbonHotkey(currentPreferences.ordinaryHotkey, id: CarbonHotkeyID.ordinary)
        registerCarbonHotkey(currentPreferences.structuredHotkey, id: CarbonHotkeyID.structured)
        registerCarbonHotkey(currentPreferences.cancelHotkey, id: CarbonHotkeyID.commit)
    }

    private func registerCarbonHotkey(_ shortcut: HotkeyShortcut, id: UInt32) {
        guard shortcut.kind == .key,
              let modifiers = shortcut.carbonModifierFlags,
              shortcut.keyCode >= 0,
              shortcut.keyCode <= Int64(UInt32.max) else {
            return
        }

        if let hotkeyRef = registerCarbonHotkey(keyCode: UInt32(shortcut.keyCode), modifiers: modifiers, id: id) {
            registeredHotkeys.append(hotkeyRef)
        }
    }

    private func registerCarbonHotkey(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var hotkeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: CarbonHotkeyID.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard status == noErr else {
            return nil
        }
        return hotkeyRef
    }

    private func registerActiveSessionSpaceHotkey() {
        guard activeSessionSpaceHotkey == nil else {
            return
        }
        activeSessionSpaceHotkey = registerCarbonHotkey(
            keyCode: UInt32(HotkeyKeyCode.space),
            modifiers: 0,
            id: CarbonHotkeyID.activeSessionSpaceCommit
        )
    }

    private func unregisterActiveSessionSpaceHotkey() {
        if let activeSessionSpaceHotkey {
            UnregisterEventHotKey(activeSessionSpaceHotkey)
        }
        activeSessionSpaceHotkey = nil
    }

    private func registerActiveSessionDiscardHotkey(_ shortcut: HotkeyShortcut) {
        guard activeSessionDiscardHotkey == nil,
              shortcut.kind == .key,
              shortcut.keyCode != HotkeyKeyCode.space,
              let modifiers = shortcut.carbonModifierFlags,
              shortcut.keyCode >= 0,
              shortcut.keyCode <= Int64(UInt32.max) else {
            return
        }
        activeSessionDiscardHotkey = registerCarbonHotkey(
            keyCode: UInt32(shortcut.keyCode),
            modifiers: modifiers,
            id: CarbonHotkeyID.activeSessionDiscard
        )
    }

    private func unregisterActiveSessionHotkeys() {
        unregisterActiveSessionSpaceHotkey()
        if let activeSessionDiscardHotkey {
            UnregisterEventHotKey(activeSessionDiscardHotkey)
        }
        activeSessionDiscardHotkey = nil
    }

    private func unregisterCarbonHotkeys() {
        for hotkey in registeredHotkeys {
            UnregisterEventHotKey(hotkey)
        }
        registeredHotkeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func handleCarbonHotkey(id: UInt32) {
        switch id {
        case CarbonHotkeyID.ordinary:
            handler(.toggleOrdinary)
        case CarbonHotkeyID.structured:
            handler(.toggleStructured)
        case CarbonHotkeyID.commit, CarbonHotkeyID.activeSessionSpaceCommit:
            handler(.commitCurrent)
        case CarbonHotkeyID.activeSessionDiscard:
            handler(.discard)
        default:
            break
        }
    }

    private func handle(_ snapshot: HotkeyEventSnapshot) {
        guard let action = parser.action(for: snapshot, preferences: preferences()) else {
            return
        }
        handle(action)
    }

    private func handle(_ action: HotkeyAction) {
        handler(action)
    }
}

private enum CarbonHotkeyID {
    static let signature: OSType = 0x564F4943
    static let ordinary: UInt32 = 1
    static let structured: UInt32 = 2
    static let commit: UInt32 = 3
    static let activeSessionSpaceCommit: UInt32 = 4
    static let activeSessionDiscard: UInt32 = 5
}

private final class HotkeyEventTapContext: @unchecked Sendable {
    let service: HotkeyService
    let sessionActivity: HotkeySessionActivity

    init(service: HotkeyService, sessionActivity: HotkeySessionActivity) {
        self.service = service
        self.sessionActivity = sessionActivity
    }
}

final class HotkeySessionActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var activeValue = false

    var isActive: Bool {
        lock.withLock { activeValue }
    }

    func claim(_ action: HotkeyAction?) -> HotkeyAction? {
        lock.withLock {
            guard activeValue, let action else {
                return nil
            }
            activeValue = false
            return action
        }
    }

    func setActive(_ isActive: Bool) {
        lock.withLock {
            activeValue = isActive
        }
    }
}

enum HotkeyKeyCode {
    static let z: Int64 = 6
    static let x: Int64 = 7
    static let space: Int64 = 49
    static let escape: Int64 = 53
    static let function: Int64 = 63
}

enum HotkeyEventKind {
    case keyDown
    case flagsChanged
}

struct HotkeyEventSnapshot {
    let kind: HotkeyEventKind
    let keyCode: Int64
    let hasFunctionFlag: Bool
    let modifierFlags: UInt64

    init(kind: HotkeyEventKind, keyCode: Int64, hasFunctionFlag: Bool, modifierFlags: UInt64 = 0) {
        self.kind = kind
        self.keyCode = keyCode
        self.hasFunctionFlag = hasFunctionFlag
        self.modifierFlags = HotkeyShortcut.normalizedModifierFlags(
            modifierFlags | (hasFunctionFlag ? HotkeyModifier.function.rawValue : 0)
        )
    }

    init?(type: CGEventType, event: CGEvent) {
        let kind: HotkeyEventKind
        switch type {
        case .keyDown:
            kind = .keyDown
        case .flagsChanged:
            kind = .flagsChanged
        default:
            return nil
        }
        self.init(
            kind: kind,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            hasFunctionFlag: event.flags.contains(.maskSecondaryFn),
            modifierFlags: event.flags.rawValue
        )
    }

    init?(event: NSEvent) {
        let kind: HotkeyEventKind
        switch event.type {
        case .keyDown:
            kind = .keyDown
        case .flagsChanged:
            kind = .flagsChanged
        default:
            return nil
        }
        self.init(
            kind: kind,
            keyCode: Int64(event.keyCode),
            hasFunctionFlag: event.modifierFlags.contains(.function),
            modifierFlags: UInt64(event.modifierFlags.rawValue)
        )
    }

    var shouldRouteToParser: Bool {
        if keyCode == HotkeyKeyCode.function {
            return true
        }
        if kind == .keyDown, keyCode == HotkeyKeyCode.escape {
            return true
        }
        if kind == .keyDown, keyCode == HotkeyKeyCode.z || keyCode == HotkeyKeyCode.x {
            return true
        }
        return hasFunctionFlag
    }

    func activeSessionAction(preferences: Preferences) -> HotkeyAction? {
        switch kind {
        case .keyDown:
            if matches(preferences.resolvedDiscardHotkey) {
                return .discard
            }
            return keyCode == HotkeyKeyCode.space ? .commitCurrent : nil
        case .flagsChanged:
            return nil
        }
    }

    private func matches(_ shortcut: HotkeyShortcut) -> Bool {
        guard shortcut.kind == .key, shortcut.keyCode == keyCode else {
            return false
        }
        return modifierFlags == shortcut.modifierFlags
    }
}

final class HotkeyEventParser {
    private var isFunctionKeyDown = false
    private var chordOccurredDuringFunctionHold = false

    func action(for event: HotkeyEventSnapshot, preferences: Preferences = .defaults) -> HotkeyAction? {
        if event.kind == .flagsChanged, event.keyCode == HotkeyKeyCode.function {
            return handleFunctionFlagChange(event, preferences: preferences)
        }

        guard event.kind == .keyDown else {
            return nil
        }

        if event.keyCode == HotkeyKeyCode.escape {
            markChordIfNeeded()
            return .discard
        }

        if matches(preferences.cancelHotkey, event: event) {
            markChordIfNeeded()
            return .commitCurrent
        } else if matches(preferences.ordinaryHotkey, event: event) {
            markChordIfNeeded()
            return .toggleOrdinary
        } else if matches(preferences.structuredHotkey, event: event) {
            markChordIfNeeded()
            return .toggleStructured
        }

        return nil
    }

    private func handleFunctionFlagChange(_ event: HotkeyEventSnapshot, preferences: Preferences) -> HotkeyAction? {
        if event.hasFunctionFlag {
            isFunctionKeyDown = true
            chordOccurredDuringFunctionHold = false
            return nil
        }

        let shouldCancel = isFunctionKeyDown && !chordOccurredDuringFunctionHold
        isFunctionKeyDown = false
        chordOccurredDuringFunctionHold = false
        return shouldCancel && preferences.cancelHotkey.kind == .functionOnly ? .commitCurrent : nil
    }

    private func matches(_ shortcut: HotkeyShortcut, event: HotkeyEventSnapshot) -> Bool {
        guard shortcut.kind == .key, shortcut.keyCode == event.keyCode else {
            return false
        }
        let effectiveFlags = HotkeyShortcut.normalizedModifierFlags(
            event.modifierFlags | (isFunctionKeyDown ? HotkeyModifier.function.rawValue : 0)
        )
        return effectiveFlags == shortcut.modifierFlags
    }

    private func markChordIfNeeded() {
        if isFunctionKeyDown {
            chordOccurredDuringFunctionHold = true
        }
    }
}
