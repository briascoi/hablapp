// Grabación con AVAudioEngine: niveles en vivo para la barra, conversión a 16 kHz mono
// (formato de dictado estÃ¡ndar) y WAV en memoria para whisper.cpp. Más silenciar la salida y elegir micrófono.

import AVFoundation
import Cocoa
import CoreAudio
import AudioToolbox

final class Recorder {
    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Int16] = []
    private let lock = NSLock()
    private(set) var peak: Float = 0
    var onLevel: ((Float) -> Void)?
    private let out16k = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    func start(deviceUID: String?) throws {
        engine = AVAudioEngine()  // nuevo motor por dictado: toma bien los cambios de micrófono
        lock.lock(); samples.removeAll(keepingCapacity: true); peak = 0; lock.unlock()
        let input = engine.inputNode
        if let uid = deviceUID, var dev = Mics.deviceID(uid: uid), let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "hablapp", code: 1, userInfo: [NSLocalizedDescriptionKey: "No hay micrófono disponible"])
        }
        converter = AVAudioConverter(from: format, to: out16k)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in self?.process(buf) }
        engine.prepare()
        try engine.start()
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        if let ch = buf.floatChannelData?[0], buf.frameLength > 0 {
            var sum: Float = 0
            for i in 0..<Int(buf.frameLength) { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(buf.frameLength))
            let level = min(1, rms * 9)
            lock.lock(); peak = max(peak, rms); lock.unlock()
            onLevel?(level)
        }
        guard let converter else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: out16k, frameCapacity: cap) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buf
        }
        guard let p = out.int16ChannelData?[0], out.frameLength > 0 else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: p, count: Int(out.frameLength)))
        lock.unlock()
    }

    private func halt() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Corta y devuelve el WAV, su duración y el pico de volumen (para descartar silencios).
    func stop() -> (url: URL, seconds: Double, peak: Float) {
        halt()
        lock.lock(); let s = samples; let p = peak; lock.unlock()
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "hablapp.wav")
        try? Recorder.wav(s).write(to: url)
        return (url, Double(s.count) / 16000, p)
    }

    func cancel() { halt() }

    static func wav(_ s: [Int16]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(s.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        s.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}

struct Mic: Identifiable, Hashable {
    let id: String  // UID de CoreAudio
    let name: String
}

enum Mics {
    static func list() -> [Mic] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices.map { Mic(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func deviceID(uid: String) -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var cfUID = uid as CFString
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let st = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        return st == noErr && id != 0 ? id : nil
    }
}

// "Silenciar todo el audio mientras dictás".
enum SystemAudio {
    private static var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                             mScope: kAudioDevicePropertyScopeOutput,
                                                             mElement: kAudioObjectPropertyElementMain)
    private static func output() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr ? id : nil
    }

    static func isMuted() -> Bool? {
        guard let dev = output() else { return nil }
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &muteAddr, 0, nil, &size, &v) == noErr ? v == 1 : nil
    }

    static func setMuted(_ m: Bool) {
        guard let dev = output() else { return }
        var v: UInt32 = m ? 1 : 0
        AudioObjectSetPropertyData(dev, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}

// "Pausar la música mientras dictás": Music y Spotify, sólo si suenan, y se reanudan sólo los que pausamos.
enum MediaPause {
    private static let apps = ["com.apple.Music": "Music", "com.spotify.client": "Spotify"]

    private static func run(_ script: String) -> String {
        var err: NSDictionary?
        return NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue ?? ""  // si Automation está negado, devuelve ""
    }

    static func pause() -> [String] {
        apps.compactMap { id, name in
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else { return nil }
            let r = run("tell application \"\(name)\"\nif player state is playing then\npause\nreturn \"ok\"\nend if\nreturn \"\"\nend tell")
            return r == "ok" ? id : nil
        }
    }

    static func resume(_ ids: [String]) {
        for id in ids {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty, let name = apps[id] else { continue }
            _ = run("tell application \"\(name)\" to play")
        }
    }
}
