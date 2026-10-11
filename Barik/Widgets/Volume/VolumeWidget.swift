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

/// A Control Center style popup with a native slider and a mute button.
struct VolumePopup: View {
    @ObservedObject private var volumeManager = VolumeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound")
                .font(.headline)
            if let volume = volumeManager.volume {
                HStack(spacing: 10) {
                    Button {
                        volumeManager.setMuted(!volumeManager.isMuted)
                    } label: {
                        Image(systemName: VolumeSymbol.name(volume: volume, muted: volumeManager.isMuted))
                            .frame(width: 20)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    // The popup panel becomes key when shown, which otherwise draws a focus ring on this button.
                    .focusEffectDisabled()
                    .help(volumeManager.isMuted ? "Unmute" : "Mute")

                    Slider(
                        value: Binding(
                            get: { Double(volume) },
                            set: { volumeManager.setVolume(Float($0)) }),
                        in: 0...1
                    )
                    .controlSize(.small)
                    .tint(.white)

                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            } else {
                Text("This output device has no volume control")
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 240, alignment: .leading)
        .padding(24)
    }
}
