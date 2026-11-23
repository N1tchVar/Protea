import AppKit
import SwiftTerm

/// The Aegean at night: deep navy ground, azure light, white marble. Same palette as the website.
enum Palette {
    static let ink = NSColor(hex: 0x040914)
    static let canvas = NSColor(hex: 0x050B19)
    static let sidebar = NSColor(hex: 0x060E1F)
    static let pane = NSColor(hex: 0x081124)
    static let header = NSColor(hex: 0x0B1730)
    static let raised = NSColor(hex: 0x0F1F3D)
    static let line = NSColor(red: 150 / 255, green: 190 / 255, blue: 1, alpha: 0.11)
    static let lineStrong = NSColor(red: 150 / 255, green: 190 / 255, blue: 1, alpha: 0.22)
    static let marble = NSColor(hex: 0xEEF4FF)
    static let marble2 = NSColor(hex: 0xA8B9D4)
    static let marble3 = NSColor(hex: 0x6C7F9E)
    static let azure = NSColor(hex: 0x4AA3FF)
    static let azureDeep = NSColor(hex: 0x2B7DE9)
    static let sky = NSColor(hex: 0x9FD0FF)
    static let coral = NSColor(hex: 0xFF7A66)
    static let sea = NSColor(hex: 0x4FD1B0)
    static let terminalText = NSColor(hex: 0xD6E2F3)

    /// 16 ANSI colours tuned for the navy ground.
    static let ansi: [SwiftTerm.Color] = {
        let hexes: [UInt32] = [
            0x1B2638, 0xFF7A66, 0x4FD1B0, 0xF2C46D, 0x4AA3FF, 0xE58FCB, 0x6CD3E8, 0xC9D7EC,
            0x3A4A63, 0xFF9A8A, 0x79E3C6, 0xF7D48F, 0x7CC0FF, 0xF0A8DA, 0x94E4F2, 0xEEF4FF,
        ]
        return hexes.map { (hex: UInt32) -> SwiftTerm.Color in
            let r = UInt16((hex >> 16) & 0xFF) * 257
            let g = UInt16((hex >> 8) & 0xFF) * 257
            let b = UInt16(hex & 0xFF) * 257
            return SwiftTerm.Color(red: r, green: g, blue: b)
        }
    }()
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum Brand {
    /// The Protea mark, copied into the app bundle by the build script.
    static let mark: NSImage? = Bundle.main.image(forResource: "protea-mark")
}

extension String {
    /// `~/code/halcyon` instead of `/Users/me/code/halcyon`.
    var abbreviatingHome: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }

    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

