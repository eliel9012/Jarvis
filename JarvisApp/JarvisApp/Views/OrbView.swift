import SwiftUI

/// Orbe central abstrato, animado conforme o estado do Jarvis.
struct OrbView: View {
    let state: JarvisState

    @State private var breathing = false
    @State private var pulsing = false

    private var color: Color {
        switch state {
        case .idle: return .blue
        case .listening: return .green
        case .transcribing: return .orange
        case .thinking: return .purple
        case .speaking: return .cyan
        case .error: return .red
        }
    }

    private var speed: Double {
        switch state {
        case .idle: return 0.35
        case .listening: return 0.8
        case .transcribing: return 1.0
        case .thinking: return 1.4
        case .speaking: return 1.2
        case .error: return 0.5
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.55), color.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 150
                    )
                )
                .blur(radius: 18)
                .scaleEffect(breathing ? 1.15 : 0.9)
                .animation(.easeInOut(duration: 2.2 / speed).repeatForever(autoreverses: true), value: breathing)

            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color, .clear, color.opacity(0.3), .clear, color]),
                        center: .center
                    )
                )
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(pulsing ? 360 : 0))
                .animation(.linear(duration: 6 / speed).repeatForever(autoreverses: false), value: pulsing)

            Circle()
                .fill(color)
                .frame(width: 70, height: 70)
                .shadow(color: color.opacity(0.8), radius: 30)
                .scaleEffect(breathing ? 1.08 : 0.92)
                .animation(.easeInOut(duration: 1.6 / speed).repeatForever(autoreverses: true), value: breathing)
        }
        .frame(width: 260, height: 260)
        .onAppear {
            breathing = true
            pulsing = true
        }
    }
}
