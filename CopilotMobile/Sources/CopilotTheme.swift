import SwiftUI

enum CopilotTheme {
    // GitHub dark backgrounds
    static let background    = Color(red: 0.051, green: 0.067, blue: 0.090)  // #0d1117
    static let surface       = Color(red: 0.086, green: 0.106, blue: 0.133)  // #161b22
    static let border        = Color(red: 0.188, green: 0.212, blue: 0.239)  // #30363d

    // Copilot purple accent
    static let accent        = Color(red: 0.431, green: 0.251, blue: 0.788)  // #6e40c9
    static let accentLight   = Color(red: 0.694, green: 0.537, blue: 0.973)  // #b189f8

    // Text
    static let textPrimary   = Color(red: 0.902, green: 0.929, blue: 0.953)  // #e6edf3
    static let textSecondary = Color(red: 0.545, green: 0.580, blue: 0.620)  // #8b949e

    // Status
    static let success       = Color(red: 0.494, green: 0.906, blue: 0.529)  // #7ee787
    static let danger        = Color(red: 0.953, green: 0.345, blue: 0.345)  // #f34545
}
