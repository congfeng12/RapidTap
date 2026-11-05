import Foundation

/// 常用虚拟键码（Carbon HIToolbox 键码，美式键盘布局）
enum KeyCode {
    static let escape: UInt16 = 53
    static let f6: UInt16 = 97
}

/// 虚拟键码到可读名称的映射，用于界面展示
enum KeyNames {

    private static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        55: "Command", 56: "Shift", 57: "CapsLock", 58: "Option", 59: "Control",
        60: "RightShift", 61: "RightOption", 62: "RightControl",
        64: "F17", 65: "Keypad.", 67: "Keypad*", 69: "Keypad+",
        71: "KeypadClear", 75: "Keypad/", 76: "KeypadEnter", 78: "Keypad-",
        79: "F18", 80: "F19", 81: "Keypad=",
        82: "Keypad0", 83: "Keypad1", 84: "Keypad2", 85: "Keypad3", 86: "Keypad4",
        87: "Keypad5", 88: "Keypad6", 89: "Keypad7", 91: "Keypad8", 92: "Keypad9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "PageUp",
        117: "ForwardDelete", 118: "F4", 119: "End", 120: "F2", 121: "PageDown",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    /// 按键显示名
    /// - Parameter code: 虚拟键码
    /// - Returns: 可读名称；未知键码返回 "键码 N"
    static func name(for code: UInt16) -> String {
        table[code] ?? "键码 \(code)"
    }
}
