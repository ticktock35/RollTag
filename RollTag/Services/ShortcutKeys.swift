import AppKit
import Carbon

enum ShortcutKeys {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let w: UInt16 = 13
    static let p: UInt16 = 35
    static let leftBracket: UInt16 = 33
    static let rightBracket: UInt16 = 30
    static let comma: UInt16 = 43
    static let period: UInt16 = 47
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let `return`: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static func wasdDirection(keyCode: UInt16) -> GridNavigation.Direction? {
        switch keyCode {
        case w: return .up
        case a: return .left
        case s: return .down
        case d: return .right
        default: return nil
        }
    }

    static func arrowDirection(keyCode: UInt16) -> GridNavigation.Direction? {
        switch keyCode {
        case leftArrow: return .left
        case rightArrow: return .right
        case upArrow: return .up
        case downArrow: return .down
        default: return nil
        }
    }

    static func isReturnKey(_ keyCode: UInt16) -> Bool {
        keyCode == `return` || keyCode == keypadEnter
    }

    static func isUSLetter(_ keyCode: UInt16) -> Bool {
        guard let character = usCharacter(keyCode: keyCode), character.count == 1 else { return false }
        return character.first?.isLetter == true
    }

    static func usCharacter(keyCode: UInt16) -> String? {
        let letters: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
            31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k",
            45: "n", 46: "m"
        ]
        return letters[keyCode]
    }

    static func latinLetter(keyCode: UInt16) -> String? {
        if let letter = usCharacter(keyCode: keyCode) { return letter }
        if keyCode == space { return " " }
        return nil
    }

    static func displayName(keyCode: UInt16) -> String {
        switch keyCode {
        case space: return String(localized: "shortcuts.key.space")
        case escape: return "Esc"
        case `return`, keypadEnter: return String(localized: "shortcuts.key.return")
        case leftArrow: return "←"
        case rightArrow: return "→"
        case upArrow: return "↑"
        case downArrow: return "↓"
        case leftBracket: return "["
        case rightBracket: return "]"
        case comma: return ","
        case period: return "."
        case 48: return "Tab"
        case 51: return "Delete"
        case 117: return "Fwd Del"
        default:
            if let letter = usCharacter(keyCode: keyCode) {
                return letter.uppercased()
            }
            if let digit = [
                18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0"
            ][keyCode] {
                return digit
            }
            return "Key \(keyCode)"
        }
    }

    static func looksLikeIMECharacter(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return text.unicodeScalars.contains { !$0.isASCII }
    }

    static func isInputMethodActive() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        if let rawType = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) {
            let type = Unmanaged<CFString>.fromOpaque(rawType).takeUnretainedValue() as String
            if type == "TISTypeKeyboardInputMethod" || type == "TISTypeKeyboardInputMethodModeEnabled" {
                return true
            }
        }
        if let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
            let lowered = id.lowercased()
            if lowered.contains("inputmethod") || lowered.contains("scim") || lowered.contains("tcim") {
                return true
            }
        }
        return false
    }

    static func shouldHintSwitchInputSource(
        characters: String?,
        keyCode: UInt16,
        boundLetterKeyCodes: Set<UInt16>? = nil
    ) -> Bool {
        if looksLikeIMECharacter(characters) { return true }
        let letterKeys = boundLetterKeyCodes ?? Set([a, s, d, p])
        return isInputMethodActive() && letterKeys.contains(keyCode)
    }
}
