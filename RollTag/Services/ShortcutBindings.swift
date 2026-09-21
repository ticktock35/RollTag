import AppKit
import Foundation

struct ShortcutBinding: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.significantModifiers)
    }

    static let significantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifiers = UInt(modifiers.intersection(Self.significantModifiers).rawValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
    }

    func matches(_ event: NSEvent, allowingShift: Bool = false) -> Bool {
        matches(keyCode: event.keyCode, modifiers: event.modifierFlags, allowingShift: allowingShift)
    }

    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, allowingShift: Bool = false) -> Bool {
        let eventMods = modifiers.intersection(Self.significantModifiers)
        let required = modifierFlags
        let extraAllowed: NSEvent.ModifierFlags = allowingShift ? .shift.subtracting(required) : []
        let stripped = eventMods.subtracting(extraAllowed)
        guard stripped == required else { return false }
        if ShortcutKeys.isReturnKey(self.keyCode) {
            return ShortcutKeys.isReturnKey(keyCode)
        }
        return keyCode == self.keyCode
    }

    var displayLabel: String {
        var label = ""
        if modifierFlags.contains(.control) { label += "⌃" }
        if modifierFlags.contains(.option) { label += "⌥" }
        if modifierFlags.contains(.shift) { label += "⇧" }
        if modifierFlags.contains(.command) { label += "⌘" }
        label += ShortcutKeys.displayName(keyCode: keyCode)
        return label
    }
}

enum ShortcutContext: String, CaseIterable, Identifiable {
    case playback
    case library
    case duplicates

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .playback: return "shortcuts.section.playback"
        case .library: return "shortcuts.section.library"
        case .duplicates: return "shortcuts.section.duplicates"
        }
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case playPause
    case fullscreen
    case previousMedia
    case nextMedia
    case confirmAI
    case clearSelection
    case gridLeft
    case gridRight
    case gridUp
    case gridDown
    case duplicateKeepLeft
    case duplicateKeepRight
    case duplicateKeepAll
    case duplicateConfirmTrash
    case duplicateCancelTrash

    var id: String { rawValue }

    var context: ShortcutContext {
        switch self {
        case .playPause, .fullscreen, .previousMedia, .nextMedia:
            return .playback
        case .confirmAI, .clearSelection, .gridLeft, .gridRight, .gridUp, .gridDown:
            return .library
        case .duplicateKeepLeft, .duplicateKeepRight, .duplicateKeepAll, .duplicateConfirmTrash, .duplicateCancelTrash:
            return .duplicates
        }
    }

    var localizationKey: String {
        switch self {
        case .playPause: return "player.playPause"
        case .fullscreen: return "player.fullscreen"
        case .previousMedia: return "player.previous"
        case .nextMedia: return "player.next"
        case .confirmAI: return "ai.confirm"
        case .clearSelection: return "shortcuts.action.escape"
        case .gridLeft: return "shortcuts.action.gridLeft"
        case .gridRight: return "shortcuts.action.gridRight"
        case .gridUp: return "shortcuts.action.gridUp"
        case .gridDown: return "shortcuts.action.gridDown"
        case .duplicateKeepLeft: return "shortcuts.action.keepLeft"
        case .duplicateKeepRight: return "shortcuts.action.keepRight"
        case .duplicateKeepAll: return "shortcuts.action.keepAll"
        case .duplicateConfirmTrash: return "shortcuts.action.confirmTrash"
        case .duplicateCancelTrash: return "shortcuts.action.cancelTrash"
        }
    }

    var defaultBinding: ShortcutBinding {
        switch self {
        case .playPause: return ShortcutBinding(keyCode: ShortcutKeys.space)
        case .fullscreen: return ShortcutBinding(keyCode: ShortcutKeys.p)
        case .previousMedia: return ShortcutBinding(keyCode: ShortcutKeys.leftBracket)
        case .nextMedia: return ShortcutBinding(keyCode: ShortcutKeys.rightBracket)
        case .confirmAI, .duplicateConfirmTrash: return ShortcutBinding(keyCode: ShortcutKeys.return)
        case .clearSelection, .duplicateCancelTrash: return ShortcutBinding(keyCode: ShortcutKeys.escape)
        case .gridLeft: return ShortcutBinding(keyCode: ShortcutKeys.leftArrow)
        case .gridRight: return ShortcutBinding(keyCode: ShortcutKeys.rightArrow)
        case .gridUp: return ShortcutBinding(keyCode: ShortcutKeys.upArrow)
        case .gridDown: return ShortcutBinding(keyCode: ShortcutKeys.downArrow)
        case .duplicateKeepLeft: return ShortcutBinding(keyCode: ShortcutKeys.a)
        case .duplicateKeepRight: return ShortcutBinding(keyCode: ShortcutKeys.d)
        case .duplicateKeepAll: return ShortcutBinding(keyCode: ShortcutKeys.s)
        }
    }

    var allowsShift: Bool {
        switch self {
        case .gridLeft, .gridRight, .gridUp, .gridDown, .previousMedia, .nextMedia: return true
        default: return false
        }
    }

    var gridDirection: GridNavigation.Direction? {
        switch self {
        case .gridLeft: return .left
        case .gridRight: return .right
        case .gridUp: return .up
        case .gridDown: return .down
        default: return nil
        }
    }

    static func actions(in context: ShortcutContext) -> [ShortcutAction] {
        allCases.filter { $0.context == context }
    }

    static func conflictPool(for action: ShortcutAction) -> [ShortcutAction] {
        switch action {
        case .playPause, .fullscreen, .previousMedia, .nextMedia:
            return actions(in: .playback) + actions(in: .library) + actions(in: .duplicates)
        case .confirmAI, .clearSelection, .gridLeft, .gridRight, .gridUp, .gridDown:
            return actions(in: .playback) + actions(in: .library)
        case .duplicateKeepLeft, .duplicateKeepRight, .duplicateKeepAll, .duplicateConfirmTrash, .duplicateCancelTrash:
            return actions(in: .playback) + actions(in: .duplicates)
        }
    }
}

struct ShortcutPreference: Codable, Equatable {
    var overrides: [String: ShortcutBinding]

    static var empty: ShortcutPreference { ShortcutPreference(overrides: [:]) }

    enum CodingKeys: String, CodingKey {
        case overrides
    }

    init(overrides: [String: ShortcutBinding] = [:]) {
        self.overrides = overrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overrides = try container.decodeIfPresent([String: ShortcutBinding].self, forKey: .overrides) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overrides, forKey: .overrides)
    }

    func binding(for action: ShortcutAction) -> ShortcutBinding {
        overrides[action.rawValue] ?? action.defaultBinding
    }

    func matches(_ event: NSEvent, _ action: ShortcutAction) -> Bool {
        matches(keyCode: event.keyCode, modifiers: event.modifierFlags, action)
    }

    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, _ action: ShortcutAction) -> Bool {
        binding(for: action).matches(keyCode: keyCode, modifiers: modifiers, allowingShift: action.allowsShift)
    }

    func libraryGridDirection(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> GridNavigation.Direction? {
        for action: ShortcutAction in [.gridLeft, .gridRight, .gridUp, .gridDown] {
            if matches(keyCode: keyCode, modifiers: modifiers, action) {
                return action.gridDirection
            }
        }
        let mods = modifiers.intersection(ShortcutBinding.significantModifiers)
        guard mods.subtracting(.shift).isEmpty else { return nil }
        guard let direction = ShortcutKeys.wasdDirection(keyCode: keyCode) else { return nil }
        for action: ShortcutAction in [.playPause, .fullscreen, .previousMedia, .nextMedia, .confirmAI, .clearSelection] {
            if matches(keyCode: keyCode, modifiers: modifiers, action) {
                return nil
            }
        }
        return direction
    }

    func fullscreenStepDelta(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Int? {
        if matches(keyCode: keyCode, modifiers: modifiers, .previousMedia) { return -1 }
        if matches(keyCode: keyCode, modifiers: modifiers, .nextMedia) { return 1 }
        let mods = modifiers.intersection(ShortcutBinding.significantModifiers)
        guard mods.subtracting(.shift).isEmpty else { return nil }
        for action: ShortcutAction in [
            .playPause, .fullscreen, .previousMedia, .nextMedia, .confirmAI, .clearSelection,
            .gridLeft, .gridRight, .gridUp, .gridDown,
            .duplicateKeepLeft, .duplicateKeepRight, .duplicateKeepAll, .duplicateConfirmTrash, .duplicateCancelTrash,
        ] {
            if matches(keyCode: keyCode, modifiers: modifiers, action) {
                return nil
            }
        }
        switch keyCode {
        case ShortcutKeys.leftBracket, ShortcutKeys.comma:
            return -1
        case ShortcutKeys.rightBracket, ShortcutKeys.period:
            return 1
        default:
            return nil
        }
    }

    func displayLabel(for action: ShortcutAction) -> String {
        binding(for: action).displayLabel
    }

    func cheatsheetLabel(for action: ShortcutAction) -> String {
        let primary = displayLabel(for: action)
        let alias: String
        switch action {
        case .gridLeft: alias = "A"
        case .gridRight: alias = "D"
        case .gridUp: alias = "W"
        case .gridDown: alias = "S"
        case .previousMedia: alias = ","
        case .nextMedia: alias = "."
        default:
            return primary
        }
        if primary.compare(alias, options: .caseInsensitive) == .orderedSame {
            return primary
        }
        return "\(primary) / \(alias)"
    }

    func conflict(assigning binding: ShortcutBinding, to action: ShortcutAction) -> ShortcutAction? {
        for other in ShortcutAction.conflictPool(for: action) where other != action {
            let existing = self.binding(for: other)
            let sameKey = existing.keyCode == binding.keyCode
                || (ShortcutKeys.isReturnKey(existing.keyCode) && ShortcutKeys.isReturnKey(binding.keyCode))
            if sameKey, existing.modifierFlags == binding.modifierFlags {
                return other
            }
        }
        return nil
    }

    mutating func set(_ binding: ShortcutBinding?, for action: ShortcutAction) {
        if let binding, binding != action.defaultBinding {
            overrides[action.rawValue] = binding
        } else {
            overrides[action.rawValue] = nil
        }
    }

    var letterKeyCodes: Set<UInt16> {
        var keys = Set(ShortcutAction.allCases.compactMap { action -> UInt16? in
            let binding = self.binding(for: action)
            guard binding.modifierFlags.isEmpty, ShortcutKeys.isUSLetter(binding.keyCode) else { return nil }
            return binding.keyCode
        })
        keys.formUnion([ShortcutKeys.w, ShortcutKeys.a, ShortcutKeys.s, ShortcutKeys.d])
        return keys
    }

    var playbackHint: String {
        String(
            format: String(localized: "player.shortcuts"),
            locale: .current,
            displayLabel(for: .playPause),
            cheatsheetLabel(for: .previousMedia),
            cheatsheetLabel(for: .nextMedia),
            displayLabel(for: .fullscreen),
            displayLabel(for: .clearSelection)
        )
    }

    var duplicatesHint: String {
        String(
            format: String(localized: "duplicates.shortcuts"),
            locale: .current,
            displayLabel(for: .duplicateKeepLeft),
            displayLabel(for: .duplicateKeepRight),
            displayLabel(for: .duplicateKeepAll),
            displayLabel(for: .duplicateConfirmTrash)
        )
    }
}
