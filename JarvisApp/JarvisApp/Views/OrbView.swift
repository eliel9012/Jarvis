import Foundation
import SwiftUI

/// Orbe central abstrato, com uma assinatura de movimento para cada etapa do pipeline.
struct OrbView: View {
    let state: JarvisState
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: JarvisState, size: CGFloat = 390) {
        self.state = state
        self.size = size
    }

    private var isStaticState: Bool {
        if case .error = state { return true }
        return false
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: reduceMotion || isStaticState)) { timeline in
            OrbComposition(
                state: state,
                time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            )
            .frame(width: 260, height: 260)
            .scaleEffect(size / 260)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct OrbComposition: View {
    let state: JarvisState
    let time: TimeInterval

    private var color: Color {
        switch state {
        case .idle: return JarvisTheme.cyan.opacity(0.72)
        case .listening: return JarvisTheme.cyan
        case .transcribing: return JarvisTheme.cyanBright
        case .thinking: return Color(red: 0.24, green: 0.56, blue: 1.0)
        case .synthesizing: return JarvisTheme.cyan
        case .speaking: return JarvisTheme.cyanBright
        case .error: return .red
        }
    }

    private var tempo: Double {
        switch state {
        case .idle: return 0.65
        case .listening: return 1.35
        case .transcribing: return 1.05
        case .thinking: return 1.5
        case .synthesizing: return 1.2
        case .speaking: return 1.65
        case .error: return 0
        }
    }

    private var breath: CGFloat {
        CGFloat((sin(time * tempo * .pi * 2) + 1) / 2)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.52), color.opacity(0.14), .clear],
                        center: .center,
                        startRadius: 12,
                        endRadius: 126
                    )
                )
                .blur(radius: 16)
                .scaleEffect((0.93 + breath * 0.12) * 0.8)

            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.16 - Double(index) * 0.025), lineWidth: index == 0 ? 1.1 : 0.65)
                    .frame(
                        width: CGFloat(238 - index * 20),
                        height: CGFloat(238 - index * 20)
                    )
                    .scaleEffect(0.8)
            }

            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 78)
                    .stroke(
                        LinearGradient(
                            colors: [.clear, color.opacity(0.74), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
                    .frame(width: 74, height: 168)
                    .rotationEffect(.degrees(Double(index) * 30 + sin(time * 0.42) * 4))
                    .scaleEffect(0.8)
                    .blur(radius: 0.25)
            }

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(
                        from: 0.06 + Double(index) * 0.16,
                        to: 0.31 + Double(index) * 0.17
                    )
                    .stroke(
                        AngularGradient(
                            colors: [.clear, color.opacity(0.96), .clear],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: index == 1 ? 2.1 : 1.2, lineCap: .round)
                    )
                    .frame(width: CGFloat(214 - index * 28), height: CGFloat(214 - index * 28))
                    .rotationEffect(.degrees(time * Double(index.isMultiple(of: 2) ? 18 : -25) + Double(index * 92)))
                    .scaleEffect(0.8)
            }

            Circle()
                .stroke(color.opacity(0.12 + breath * 0.1), lineWidth: 1)
                .frame(width: 188, height: 188)
                .scaleEffect(0.8)

            stateMotion
                .scaleEffect(0.8)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.75), color, color.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.68), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 28
                            )
                        )
                        .frame(width: 44, height: 44)
                        .offset(x: 5, y: 5)
                }
                .frame(width: 70, height: 70)
                .overlay {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 0.7)
                }
                .shadow(color: color.opacity(0.76), radius: 25 + breath * 10)
                .scaleEffect(0.95 + breath * 0.08)

            coreActivity
        }
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.55), value: state)
    }

    @ViewBuilder
    private var stateMotion: some View {
        switch state {
        case .idle:
            Circle()
                .trim(from: 0.06, to: 0.68)
                .stroke(
                    AngularGradient(colors: [color, color.opacity(0.08), color], center: .center),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .frame(width: 132, height: 132)
                .rotationEffect(.degrees(time * 12))

        case .listening:
            ForEach(0..<3, id: \.self) { index in
                let progress = normalized(time * 0.72 - Double(index) * 0.28)
                Circle()
                    .stroke(color.opacity((1 - progress) * 0.42), lineWidth: 1.5)
                    .frame(width: 102, height: 102)
                    .scaleEffect(0.78 + progress * 0.92)
            }

        case .transcribing:
            Circle()
                .trim(from: 0.03, to: 0.32)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 142, height: 142)
                .rotationEffect(.degrees(time * 150))
            Circle()
                .trim(from: 0.54, to: 0.8)
                .stroke(color.opacity(0.25), lineWidth: 1.5)
                .frame(width: 166, height: 166)
                .rotationEffect(.degrees(-time * 70))

        case .thinking:
            orbitRing(diameter: 138, trim: 0.34, width: 2.6, rotation: time * 128)
            orbitRing(diameter: 174, trim: 0.21, width: 1.4, rotation: -time * 86)
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: index == 0 ? 7 : 5, height: index == 0 ? 7 : 5)
                    .offset(x: CGFloat(69 + index * 14))
                    .rotationEffect(.degrees(time * Double(105 - index * 18) + Double(index * 120)))
                    .shadow(color: color.opacity(0.8), radius: 5)
            }

        case .synthesizing:
            ForEach(0..<3, id: \.self) { index in
                let progress = normalized(time * 0.58 + Double(index) * 0.27)
                Circle()
                    .trim(from: 0.08 + progress * 0.16, to: 0.92 - progress * 0.16)
                    .stroke(color.opacity(0.12 + (1 - progress) * 0.32), lineWidth: 1.4)
                    .frame(width: CGFloat(118 + index * 26), height: CGFloat(118 + index * 26))
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? time * 34 : -time * 34))
            }

        case .speaking:
            ForEach(0..<3, id: \.self) { index in
                let progress = normalized(time * 1.05 - Double(index) * 0.22)
                Circle()
                    .stroke(color.opacity((1 - progress) * 0.34), lineWidth: 2)
                    .frame(width: 94, height: 94)
                    .scaleEffect(0.9 + progress * 1.18)
            }

        case .error:
            Circle()
                .stroke(color.opacity(0.65), style: StrokeStyle(lineWidth: 2, dash: [5, 7]))
                .frame(width: 142, height: 142)
        }
    }

    @ViewBuilder
    private var coreActivity: some View {
        switch state {
        case .listening:
            Image(systemName: "mic")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))

        case .transcribing:
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 3, height: 8 + wave(index: index, amplitude: 12, frequency: 3.2))
                }
            }

        case .thinking:
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: 5, height: 5)
                    .offset(x: 13)
                    .rotationEffect(.degrees(time * 180 + Double(index * 120)))
            }

        case .synthesizing:
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 3, height: 6 + wave(index: index, amplitude: 16, frequency: 4.4))
                }
            }

        case .speaking:
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: 4, height: 8 + wave(index: index, amplitude: 20, frequency: 6.2))
                }
            }

        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)

        case .idle:
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 8, height: 8)
        }
    }

    private func orbitRing(diameter: CGFloat, trim: CGFloat, width: CGFloat, rotation: Double) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(
                AngularGradient(colors: [color.opacity(0.12), color, color.opacity(0.12)], center: .center),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(rotation))
    }

    private func wave(index: Int, amplitude: CGFloat, frequency: Double) -> CGFloat {
        let value = (sin(time * frequency + Double(index) * 0.88) + 1) / 2
        return CGFloat(value) * amplitude
    }

    private func normalized(_ value: Double) -> CGFloat {
        CGFloat(value - floor(value))
    }
}

/// Abertura inspirada em timelines, stagger e eases do GSAP, implementada nativamente em SwiftUI.
struct LaunchSequenceView: View {
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0

    private let letters = Array("JARVIS")

    var body: some View {
        ZStack {
            JarvisBackground()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [JarvisTheme.cyan.opacity(0.24), JarvisTheme.cyan.opacity(0.05), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 170
                    )
                )
                .frame(width: 340, height: 340)
                .blur(radius: 15)
                .scaleEffect(stage >= 1 ? 1 : 0.45)
                .opacity(stage >= 1 ? 1 : 0)

            VStack(spacing: 22) {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(JarvisTheme.cyan.opacity(0.28 - Double(index) * 0.05), lineWidth: 1)
                            .frame(width: CGFloat(108 + index * 28), height: CGFloat(108 + index * 28))
                            .scaleEffect(stage >= 1 ? 1 : 0.35)
                            .opacity(stage >= 1 ? 1 : 0)
                            .animation(
                                .timingCurve(0.16, 1, 0.3, 1, duration: 0.72)
                                    .delay(Double(index) * 0.07),
                                value: stage
                            )
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [JarvisTheme.cyanBright.opacity(0.78), JarvisTheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: JarvisTheme.cyan.opacity(0.58), radius: 28)
                        .scaleEffect(stage >= 1 ? 1 : 0.2)
                        .opacity(stage >= 1 ? 1 : 0)
                }
                .frame(height: 176)

                HStack(spacing: 2) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                        Text(String(letter))
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .tracking(-1)
                            .offset(y: stage >= 2 ? 0 : 24)
                            .opacity(stage >= 2 ? 1 : 0)
                            .blur(radius: stage >= 2 ? 0 : 6)
                            .animation(
                                .timingCurve(0.16, 1, 0.3, 1, duration: 0.58)
                                    .delay(Double(index) * 0.055),
                                value: stage
                            )
                    }
                }

                Text("LOCAL  •  PRIVADO  •  PT-BR")
                    .font(.caption.weight(.semibold))
                    .tracking(2.2)
                    .foregroundStyle(.secondary)
                    .offset(y: stage >= 3 ? 0 : 10)
                    .opacity(stage >= 3 ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .task {
            guard stage == 0 else { return }
            do {
                if reduceMotion {
                    stage = 3
                    try await Task.sleep(nanoseconds: 180_000_000)
                    onComplete()
                    return
                }

                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)) {
                    stage = 1
                }
                try await Task.sleep(nanoseconds: 300_000_000)
                stage = 2
                try await Task.sleep(nanoseconds: 560_000_000)
                withAnimation(.easeOut(duration: 0.35)) {
                    stage = 3
                }
                try await Task.sleep(nanoseconds: 620_000_000)
                onComplete()
            } catch {
                // A task é cancelada quando a janela fecha; não há trabalho a concluir.
            }
        }
    }
}
