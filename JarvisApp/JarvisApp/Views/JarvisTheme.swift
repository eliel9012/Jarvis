import SwiftUI

enum JarvisTheme {
    static let background = Color(red: 0.015, green: 0.035, blue: 0.065)
    static let backgroundRaised = Color(red: 0.035, green: 0.065, blue: 0.11)
    static let panel = Color(red: 0.055, green: 0.085, blue: 0.135)
    static let border = Color(red: 0.27, green: 0.38, blue: 0.52)
    static let cyan = Color(red: 0.28, green: 0.82, blue: 1.0)
    static let cyanBright = Color(red: 0.62, green: 0.94, blue: 1.0)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color(red: 0.66, green: 0.70, blue: 0.79)
}

struct JarvisBackground: View {
    var body: some View {
        ZStack {
            JarvisTheme.background
            RadialGradient(
                colors: [Color.blue.opacity(0.15), .clear],
                center: UnitPoint(x: 0.5, y: 0.34),
                startRadius: 10,
                endRadius: 590
            )
            LinearGradient(
                colors: [Color.black.opacity(0.02), Color.black.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct JarvisIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(JarvisTheme.primaryText)
                .frame(width: 38, height: 38)
                .background(JarvisTheme.panel.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(JarvisTheme.border.opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
