// Transcripción: Apple SpeechAnalyzer (por defecto, el modelo lo baja macOS) o whisper.cpp (opcional).

import Foundation
import AVFoundation
import Speech

enum Transcriber {
    static var engine: String { UserDefaults.standard.string(forKey: "engine") ?? "apple" }

    // MARK: whisper.cpp

    static var whisperBinary: String? {
        ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func modelsDir() -> URL {
        let dirs = ["~/.cache/hyperframes/whisper/models", "~/Library/Application Support/hablapp/models"]
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
        return dirs.first { d in
            ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).contains { $0.hasPrefix("ggml-") }
        } ?? dirs[0]
    }

    static var whisperAvailable: Bool {
        whisperBinary != nil && !((try? FileManager.default.contentsOfDirectory(atPath: modelsDir().path)) ?? []).filter { $0.hasPrefix("ggml-") }.isEmpty
    }

    static func whisper(_ wav: URL, binary: String) -> String {
        let d = UserDefaults.standard
        let model = modelsDir().appendingPathComponent(d.string(forKey: "model") ?? "ggml-small.bin").path
        var args = ["-m", model, "-l", d.string(forKey: "language") ?? "es", "-nt", "-np", "-f", wav.path]
        let vocab = Store.shared.words.map { $0.isReplacement ? $0.to : $0.from }
        if !vocab.isEmpty { args += ["--prompt", vocab.joined(separator: ", ")] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        // whisper marca silencios y ruidos como [BLANK_AUDIO], (música), etc.
        if text.range(of: #"^[\[\(][^\]\)]*[\]\)]$"#, options: .regularExpression) != nil { return "" }
        return text
    }

    // MARK: Apple

    /// Locale del idioma de dictado (`auto` usa el del sistema), resuelto contra los que soporta Apple.
    static func locale() async -> Locale? {
        let lang = UserDefaults.standard.string(forKey: "language") ?? "es"
        let want = lang == "auto" ? Locale.current : Locale(identifier: lang)
        return await SpeechTranscriber.supportedLocale(equivalentTo: want)
    }

    static func appleTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .transcription)
    }

    /// ¿Está instalado el modelo de voz de Apple para el idioma actual?
    static func appleModelInstalled() async -> Bool {
        guard let loc = await locale() else { return false }
        return await AssetInventory.status(forModules: [appleTranscriber(loc)]) == .installed
    }

    /// Descarga el modelo si falta (lo instala macOS, no la app).
    static func ensureAppleModel() async throws {
        guard let loc = await locale() else { throw err("Apple no soporta ese idioma") }
        let t = appleTranscriber(loc)
        if await AssetInventory.status(forModules: [t]) == .installed { return }
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
    }

    static func apple(_ wav: URL) async throws -> String {
        guard let loc = await locale() else { throw err("Apple no soporta ese idioma") }
        try await ensureAppleModel()
        let transcriber = appleTranscriber(loc)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Vocabulario del Diccionario como contexto del reconocedor.
        let vocab = Store.shared.words.map { $0.isReplacement ? $0.to : $0.from }
        if !vocab.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings[.general] = vocab
            try await analyzer.setContext(ctx)
        }
        let collect = Task { () -> String in
            var s = AttributedString()
            for try await r in transcriber.results where r.isFinal { s += r.text }
            return String(s.characters)
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: try AVAudioFile(forReading: wav)) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collect.cancel()
            throw error
        }
        return try await collect.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Transcripción del WAV completo: whisper.cpp, `--transcribe` y respaldo si falla la de en vivo.
    static func transcribe(wav: URL) async throws -> String {
        if engine == "whisper" {
            if let bin = whisperBinary, whisperAvailable {
                return whisper(wav, binary: bin)
            }
            await MainActor.run { Flow.shared.notice("whisper.cpp no está instalado, uso el motor de Apple") }
        }
        return try await apple(wav)
    }

    private static func err(_ m: String) -> NSError {
        NSError(domain: "hablapp", code: 2, userInfo: [NSLocalizedDescriptionKey: m])
    }
}

// Transcripción en vivo con el motor de Apple: el audio se analiza mientras hablás, así al soltar fn
// sólo falta cerrar el último tramo. El texto parcial (final + volátil) sale por onText en el hilo principal.
final class LiveTranscription {
    var onText: ((String) -> Void)?
    private let (raw, rawIn) = AsyncStream<AVAudioPCMBuffer>.makeStream()
    private var task: Task<String, Error>?

    func start() {
        task = Task.detached { [raw, weak self] in
            guard let loc = await Transcriber.locale() else { throw NSError(domain: "hablapp", code: 2) }
            try await Transcriber.ensureAppleModel()
            let transcriber = SpeechTranscriber(locale: loc, preset: .progressiveTranscription)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let vocab = Store.shared.words.map { $0.isReplacement ? $0.to : $0.from }
            if !vocab.isEmpty {
                let ctx = AnalysisContext()
                ctx.contextualStrings[.general] = vocab
                try await analyzer.setContext(ctx)
            }
            let src = Recorder.format
            let dst = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: src) ?? src
            try await analyzer.prepareToAnalyze(in: dst)
            let converter = dst == src ? nil : AVAudioConverter(from: src, to: dst)

            // Los tramos que llegaron mientras se preparaba el analizador esperan en `raw`.
            let (inputs, inputsIn) = AsyncStream<AnalyzerInput>.makeStream()
            let pump = Task {
                for await b in raw {
                    let out: AVAudioPCMBuffer? = if let converter { LiveTranscription.convert(b, converter, to: dst) } else { b }
                    if let out { inputsIn.yield(AnalyzerInput(buffer: out)) }
                }
                inputsIn.finish()
            }
            let results = Task { () -> String in
                var final = AttributedString()
                for try await r in transcriber.results {
                    if r.isFinal { final += r.text }
                    let shown = String((r.isFinal ? final : final + r.text).characters)
                    DispatchQueue.main.async { self?.onText?(shown) }
                }
                return String(final.characters)
            }
            try await analyzer.start(inputSequence: inputs)
            await pump.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await results.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) { rawIn.yield(buffer) }

    /// Cierra la entrada y espera el texto final.
    func finish() async throws -> String {
        rawIn.finish()
        guard let task else { return "" }
        return try await task.value
    }

    func cancel() {
        onText = nil
        rawIn.finish()
        task?.cancel()
    }

    private static func convert(_ buf: AVAudioPCMBuffer, _ converter: AVAudioConverter, to fmt: AVAudioFormat) -> AVAudioPCMBuffer? {
        let cap = AVAudioFrameCount(Double(buf.frameLength) * fmt.sampleRate / buf.format.sampleRate + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buf
        }
        return out.frameLength > 0 ? out : nil
    }
}
