import AVFoundation
import AppKit
import MediaPlayer
// Usage: nowplaying <seconds> <title> [duration]
// Plays a nearly silent tone and publishes it as the system's now playing item for <seconds>. Without a duration it
// is published like a live stream, which has none.
let args = CommandLine.arguments
let seconds = Double(args[1])!
let title = args[2]
let duration = args.count > 3 ? Double(args[3]) : nil

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let engine = AVAudioEngine()
let format = engine.outputNode.inputFormat(forBus: 0)
var phase = 0.0
let source = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
    for frame in 0..<Int(frameCount) {
        let value = Float(sin(phase) * 0.002)
        phase += 2 * .pi * 440 / format.sampleRate
        for buffer in buffers { buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = value }
    }
    return noErr
}
engine.attach(source)
try! engine.connectNode(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1))
try! engine.start()

let center = MPRemoteCommandCenter.shared()
center.playCommand.addTarget { _ in .success }
center.pauseCommand.addTarget { _ in .success }
center.togglePlayPauseCommand.addTarget { _ in .success }

var info: [String: Any] = [
    MPMediaItemPropertyTitle: title,
    MPMediaItemPropertyArtist: "Sill test",
    MPNowPlayingInfoPropertyPlaybackRate: 1.0,
]
if let duration {
    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
} else {
    info[MPNowPlayingInfoPropertyIsLiveStream] = true
}
MPNowPlayingInfoCenter.default().nowPlayingInfo = info
MPNowPlayingInfoCenter.default().playbackState = .playing
print("publishing for \(seconds) s")
fflush(stdout)

DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    exit(0)
}
app.run()
