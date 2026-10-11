import SwiftUI

/// Shows the output volume as a speaker symbol and percentage; clicking opens a slider popup.
/// Hidden when the current output device does not expose a volume.
struct VolumeWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var volumeManager = VolumeManager.shared
    var showPercentage: Bool { configProvider.config["show-percentage"]?.boolValue ?? true }

    @State private var rect: CGRect = .zero

    var body: some View {
        if let volume = volumeManager.volume {
            HStack(spacing: 5) {
                Image(systemName: VolumeSymbol.name(volume: volume, muted: volumeManager.isMuted))
                    .font(.barText)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18, alignment: .leading)
                if showPercentage {
                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.barText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(volumeManager.isMuted ? 0.5 : 1)
                }
            }
            .experimentalConfiguration(cornerRadius: 15)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                            rect = newFrame
                        }
                }
            )
            .barButton(
                label: "Volume",
                value: "\(Int((volume * 100).rounded()))%" + (volumeManager.isMuted ? ", muted" : "")
            ) {
                MenuBarPopup.show(rect: rect, id: "volume") { VolumePopup() }
            }
        }
    }
}

/// The speaker SF Symbol matching the volume, like the macOS Control Center.
enum VolumeSymbol {
    static func name(volume: Float, muted: Bool) -> String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// A Control Center style popup: a native slider with the minimum and maximum speaker icons at its ends, as the HIG
/// suggests for sliders, and a round mute button. The button is a fill rather than glass to avoid glass on glass.
struct VolumePopup: View {
    @ObservedObject private var volumeManager = VolumeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound")
                .font(.headline)
            if let volume = volumeManager.volume {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Slider(
                        value: Binding(
                            get: { Double(volume) },
                            set: { volumeManager.setVolume(Float($0)) }),
                        in: 0...1
                    )
                    .tint(Color.primary)
                    .accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Button {
                        volumeManager.setMuted(!volumeManager.isMuted)
                    } label: {
                        Image(systemName: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(volumeManager.isMuted ? 0.25 : 0.1)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(volumeManager.isMuted ? "Unmute" : "Mute")
                    .help(volumeManager.isMuted ? "Unmute" : "Mute")
                }
            } else {
                Text("This output device has no volume control")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, alignment: .leading)
        .padding(24)
    }
}
