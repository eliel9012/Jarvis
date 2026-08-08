import SwiftUI

/// Waveform simples do microfone.
struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green.opacity(0.9))
                    .frame(width: 3, height: max(4, CGFloat(level) * 36))
            }
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .opacity(levels.isEmpty ? 0 : 1)
    }
}
