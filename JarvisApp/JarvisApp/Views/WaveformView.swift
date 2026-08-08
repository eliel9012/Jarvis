import SwiftUI

/// Linha de áudio ampla. Usa níveis reais do microfone e mantém pulso sutil nos demais estados.
struct WaveformView: View {
    let levels: [Float]
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let count = max(61, min(121, Int(geometry.size.width / 8)))
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<count, id: \.self) { index in
                        let midpoint = Double(count - 1) / 2
                        let distance = abs(Double(index) - midpoint) / max(midpoint, 1)
                        let envelope = exp(-pow((distance - 0.48) / 0.19, 2))
                        let sample = sampledLevel(index: index, count: count)
                        let idleMotion = levels.isEmpty
                            ? 0.22 + abs(sin(time * 4.2 + Double(index) * 0.41)) * 0.62
                            : 0.08 + abs(sin(time * 4.2 + Double(index) * 0.41)) * 0.12
                        let live = max(Double(sample), idleMotion)
                        let amplitude = isActive ? live : 0.06
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [JarvisTheme.cyan.opacity(0.34), JarvisTheme.cyanBright],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(
                                width: index.isMultiple(of: 5) ? 2 : 1.2,
                                height: max(2, 3 + amplitude * envelope * 92)
                            )
                            .shadow(color: JarvisTheme.cyan.opacity(0.7), radius: isActive ? 4 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 100)
        .opacity(isActive ? 1 : 0.42)
        .accessibilityHidden(true)
    }

    private func sampledLevel(index: Int, count: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        let mirrored = index <= count / 2 ? index : count - 1 - index
        let ratio = Double(mirrored) / Double(max(count / 2, 1))
        let sourceIndex = min(levels.count - 1, Int(ratio * Double(levels.count - 1)))
        return levels[sourceIndex]
    }
}
