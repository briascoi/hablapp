// El motor: atajos globales (event tap), estados del dictado, transcripción (ver Speech.swift)
// y pegado donde está el cursor. Todo corre en el hilo principal salvo la transcripción y el LLM.

import Cocoa
import Carbon
import AVFoundation
import FoundationModels
import os

enum Phase: Equatable {
    case idle
    case recording(handsFree: Bool, command: Bool)
    case processing(command: Bool)
    case notice(String)
}

final class Flow: ObservableObject {
    static let shared = Flow()
    @Published var phase: Phase = .idle
    @Published var levels: [Float] = Array(repeating: 0, count: 11)
    @Published var lastText = ""
    @Published var partial = ""  // texto en vivo mientras dictás
    @Published var lastTiming = ""  // cuánto tardó el último dictado tras soltar (Ajustes > Experimental)

    func notice(_ text: String) {
        phase = .notice(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [self] in
            if phase == .notice(text) { phase = .idle }
        }
    }
}

enum Paster {
    static func snapshot() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }

    static func press(key: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    private static var vCache: [String: CGKeyCode] = [:]

    /// Keycode de la tecla "v" en el layout actual (UCKeyTranslate sobre 0 a 127, cacheado por layout). Fallback: 9.
    static func vKeyCode() -> CGKeyCode {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID),
              let dataPtr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return 9 }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        if let k = vCache[id] { return k }
        let layout = unsafeBitCast(dataPtr, to: CFData.self)
        let ptr = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var found: CGKeyCode = 9
        for code in 0..<128 {
            var dead: UInt32 = 0
            var len = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let st = UCKeyTranslate(ptr, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
            if st == noErr, len == 1, chars[0] == 0x76 { found = CGKeyCode(code); break }
        }
        vCache[id] = found
        return found
    }

    /// Pega con ⌘V y devuelve el portapapeles del usuario a los 500 ms.
    /// Con Secure Input activo (contraseñas) no pega: deja el texto copiado.
    static func paste(_ text: String, pressEnter: Bool = false) {
        let pb = NSPasteboard.general
        if IsSecureEventInputEnabled() {
            pb.clearContents()
            pb.setString(text, forType: .string)
            Flow.shared.notice("Campo seguro: el texto quedó copiado, pegalo con ⌘V")
            return
        }
        let saved = snapshot()
        pb.clearContents()
        pb.setString(text, forType: .string)
        press(key: vKeyCode(), flags: .maskCommand)
        if pressEnter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { press(key: 36) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { restore(saved) }
    }
}

enum Sounds {
    static func play(_ name: String, volume: Float = 0.35) {
        guard UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true else { return }
        let s = NSSound(named: name)
        s?.volume = volume
        s?.play()
    }
}

final class Perms: ObservableObject {
    static let shared = Perms()
    @Published var mic = false
    @Published var accessibility = false
    var allGood: Bool { mic && accessibility }

    func refresh() {
        let m = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let a = AXIsProcessTrusted()
        if m != mic { mic = m }
        if a != accessibility { accessibility = a }
    }

    func requestMic() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.refresh() } }
        } else {
            open("Privacy_Microphone")
        }
    }

    private var prompted = false

    /// La primera vez muestra el aviso de macOS, que además agrega hablapp a la lista de Accesibilidad.
    /// Después abre directo el panel: abrir los dos juntos dejaba el aviso tapado por Ajustes.
    func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return refresh() }
        if !prompted {
            prompted = true
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        } else {
            open("Privacy_Accessibility")
        }
    }

    /// Borra la entrada de hablapp en Accesibilidad (sirve cuando quedó una de una versión con otra firma).
    func resetAccessibility() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.isma.hablapp"]
        try? p.run()
        p.waitUntilExit()
        prompted = false
        refresh()
    }

    func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

final class Engine {
    static let shared = Engine()

    enum Mode { case idle, ptt, handsFree, command, busy }

    private let recorder = Recorder()
    private var tap: CFMachPort?
    private var mode = Mode.idle
    private var fnDown = false
    private var fnDownAt = Date()
    private var lastTap: Date?
    private var ignoreRelease = false
    private var session = 0  // invalida avisos demorados de un dictado anterior
    private var context = Context()
    private var warm: LanguageModelSession?
    private var wasMuted: Bool?
    private var pausedApps: [String] = []
    private var live: LiveTranscription?
    private let log = Logger(subsystem: "com.isma.hablapp", category: "dictado")

    private let defaults = UserDefaults.standard
    private var flow: Flow { Flow.shared }

    // MARK: arranque

    func start() {
        recorder.onLevel = { level in
            DispatchQueue.main.async {
                var l = Flow.shared.levels
                l.removeFirst()
                l.append(level)
                Flow.shared.levels = l
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Perms.shared.refresh()
            if self?.tap == nil { self?.installTap() }
        }
        Perms.shared.refresh()
        installTap()
    }

    func ensureTap() { if tap == nil { installTap() } }

    private func installTap() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
                                    Engine.shared.handle(type, event) ? nil : Unmanaged.passUnretained(event)
                                }, userInfo: nil)
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: atajos

    /// Devuelve true si el evento se "come" (no llega a la app activa).
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if type == .flagsChanged {
            if code == 63 {
                let down = flags.contains(.maskSecondaryFn)
                if down && !fnDown { fnDown = true; fnPressed(ctrl: flags.contains(.maskControl)) }
                else if !down && fnDown { fnDown = false; fnReleased() }
            } else if (code == 59 || code == 62), flags.contains(.maskControl), fnDown, mode == .ptt, commandEnabled {
                mode = .command  // fn + ctrl en cualquier orden
                show()
            }
            return false
        }

        // keyDown
        if fnDown && mode == .ptt {
            if code == 49 { mode = .handsFree; ignoreRelease = true; show(); return true }  // fn + espacio
            cancel(silent: true)  // fn usado como modificador (fn+flechas, fn+borrar…)
            return false
        }
        if code == 53, mode != .idle, mode != .busy { cancel(silent: false); return true }  // esc

        let mods = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if mods == [.maskCommand, .maskControl] {
            if code == 9 { pasteLast(); return true }  // ⌃⌘V
            if code == 8 { copyLast(); return true }  // ⌃⌘C
        }
        if mods == .maskAlternate, defaults.object(forKey: "transforms") as? Bool ?? true,
           let i = [18, 19, 20, 21, 23, 22, 26, 28, 25].firstIndex(of: Int(code)) {
            let list = Store.shared.transforms
            if i < list.count { runTransform(list[i]); return true }
        }
        return false
    }

    private var commandEnabled: Bool { defaults.object(forKey: "commandMode") as? Bool ?? true }

    private func fnPressed(ctrl: Bool) {
        switch mode {
        case .handsFree: ignoreRelease = true; finish()
        case .idle: begin(ctrl && commandEnabled ? .command : .ptt)
        default: break
        }
    }

    private func fnReleased() {
        if ignoreRelease { ignoreRelease = false; return }
        guard mode == .ptt || mode == .command else { return }
        let held = Date().timeIntervalSince(fnDownAt)
        if mode == .ptt && held < 0.3 {
            // Toque corto: el segundo toque seguido activa manos libres.
            if let last = lastTap, Date().timeIntervalSince(last) < 0.5 {
                lastTap = nil
                mode = .handsFree
                show()
            } else {
                lastTap = Date()
                cancel(silent: true)
            }
            return
        }
        finish()
    }

    // MARK: ciclo del dictado

    /// Clic en la barra flotante: arranca o termina en modo manos libres.
    func toggleHandsFree() {
        if mode == .idle { begin(.handsFree) } else if mode == .handsFree { finish() }
    }

    private func begin(_ m: Mode) {
        guard Perms.shared.allGood else {
            flow.notice("Faltan permisos")
            Onboarding.shared.show()
            return
        }
        mode = m
        fnDownAt = Date()
        session += 1
        if defaults.bool(forKey: "mute") {
            wasMuted = SystemAudio.isMuted()
            if wasMuted == false { SystemAudio.setMuted(true) }
        }
        if defaults.bool(forKey: "pauseMedia") { pausedApps = MediaPause.pause() }
        flow.partial = ""
        warm = nil
        if Transcriber.engine == "apple" {
            let l = LiveTranscription()
            let preview = defaults.object(forKey: "livePreview") as? Bool ?? true
            l.onText = { if preview { Flow.shared.partial = $0 } }
            live = l
            recorder.onBuffer = { l.feed($0) }
        }
        do {
            try recorder.start(deviceUID: defaults.string(forKey: "mic"))
        } catch {
            stopLive()?.cancel()
            restoreAudio()
            mode = .idle
            flow.notice("No pude usar el micrófono")
            return
        }
        // El WAV y la cola del vivo ya reciben audio mientras se lee la ventana destino.
        // Capturar antes de abrir la barra, para conservar el foco de la app donde se va a pegar.
        context = Ctx.read()
        live?.start(vocabulary: ScreenContext.vocabulary(context, words: Store.shared.words))
        flow.levels = Array(repeating: 0, count: flow.levels.count)
        if m == .handsFree { show() } else {
            // Si en 150 ms sigue apretado, mostramos barra y sonido: los toques al pasar no hacen ruido.
            let id = session
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                if id == session, mode == .ptt || mode == .command { show() }
            }
        }
        let recordingID = session
        DispatchQueue.main.async { [self] in
            guard session == recordingID, mode == .ptt || mode == .handsFree else { return }
            let useLLM = defaults.object(forKey: "aiFormat") as? Bool ?? true
            var transform = ContextTransforms.resolve(context: context, rules: Store.shared.appTransforms,
                                                      transforms: Store.shared.transforms,
                                                      general: defaults.string(forKey: "autoTransform") ?? "",
                                                      enabled: defaults.object(forKey: "transforms") as? Bool ?? true)
            if transform?.createsPrompt == true, !PromptAPI.enabled { transform = nil }
            if mode != .command, transform == nil, useLLM, LLM.available {
                warm = LanguageModelSession(instructions: Formatter.instructions(context.category, bundle: context.bundle, app: context.app))
                warm?.prewarm(promptPrefix: Prompt(Formatter.promptContext(context)))
            }
        }
    }

    private func show() {
        if case .recording = flow.phase {} else { Sounds.play("Tink") }
        flow.phase = .recording(handsFree: mode == .handsFree, command: mode == .command)
    }

    private func restoreAudio() {
        if wasMuted == false { SystemAudio.setMuted(false) }
        wasMuted = nil
        MediaPause.resume(pausedApps)
        pausedApps = []
    }

    /// Desengancha la transcripción en vivo del grabador y la devuelve (para terminarla o cancelarla).
    private func stopLive() -> LiveTranscription? {
        recorder.onBuffer = nil
        defer { live = nil }
        return live
    }

    func cancel(silent: Bool) {
        guard mode != .idle, mode != .busy else { return }
        recorder.cancel()
        stopLive()?.cancel()
        flow.partial = ""
        restoreAudio()
        mode = .idle
        session += 1
        if !silent { Sounds.play("Funk", volume: 0.25) }
        flow.phase = .idle
    }

    private func finish() {
        let m = mode
        mode = .busy
        let rec = recorder.stop()
        let live = stopLive()
        restoreAudio()
        Sounds.play("Pop", volume: 0.3)
        guard rec.seconds > 0.25, rec.peak > 0.004 else {
            live?.cancel()
            flow.partial = ""
            mode = .idle
            flow.notice("No se escuchó nada")
            return
        }
        flow.phase = .processing(command: m == .command)
        let ctx = context
        let vocabulary = ScreenContext.vocabulary(ctx, words: Store.shared.words)
        let session = warm
        warm = nil
        var chosen = ContextTransforms.resolve(context: ctx, rules: Store.shared.appTransforms,
                                                  transforms: Store.shared.transforms,
                                                  general: defaults.string(forKey: "autoTransform") ?? "",
                                                  enabled: defaults.object(forKey: "transforms") as? Bool ?? true)
        if chosen?.createsPrompt == true, !PromptAPI.enabled { chosen = nil }
        let transform = chosen
        Task.detached {
            let t0 = Date()
            let got: (String, String)
            if let live, let r = try? await live.finish(), !r.isEmpty { got = (r, "en vivo") } else {
                do { got = (try await Transcriber.transcribe(wav: rec.url, vocabulary: vocabulary), "archivo") } catch {
                    await MainActor.run { self.done(); Flow.shared.notice("No pude transcribir") }
                    return
                }
            }
            let (raw, how) = got
            let t1 = Date()
            guard !raw.isEmpty else {
                await MainActor.run { self.done(); Flow.shared.notice("No se escuchó nada") }
                return
            }
            if m == .command {
                let sel = await Ctx.selection()
                let out = await Formatter.command(raw, selection: sel)
                await MainActor.run {
                    self.done()
                    guard let out else { Flow.shared.notice("El modo comando necesita Apple Intelligence"); return }
                    Paster.paste(out)
                    self.timing(t0, t1, how: how)
                    self.record(raw: raw, text: out, seconds: rec.seconds, ctx: ctx, kind: "comando")
                }
                return
            }
            let res2 = await Formatter.dictation(raw, ctx, session: session, transform: transform)
            await MainActor.run {
                self.done()
                Paster.paste(res2.text, pressEnter: res2.pressEnter)
                if res2.transformFailed {
                    let reason = transform?.createsPrompt == true ? PromptAPIState.shared.lastError : "No se pudo aplicar el transform."
                    Flow.shared.notice(reason + " Se conservó el dictado.")
                }
                self.timing(t0, t1, how: how)
                Learner.watch(pasted: res2.text, app: ctx.bundle)
                self.record(raw: raw, text: res2.text, seconds: rec.seconds, ctx: ctx, kind: "dictado")
            }
        }
    }

    private func done() {
        mode = .idle
        flow.partial = ""
        if case .processing = flow.phase { flow.phase = .idle }
    }

    /// Tiempos tras soltar: transcripción (t0→t1) y formato hasta pegar (t1→ahora).
    private func timing(_ t0: Date, _ t1: Date, how: String) {
        func s(_ x: Double) -> String { String(format: "%.1f s", x).replacingOccurrences(of: ".", with: ",") }
        let tr = t1.timeIntervalSince(t0), fm = Date().timeIntervalSince(t1)
        flow.lastTiming = "Transcripción \(s(tr)) (\(how)) · formato \(s(fm))"
        log.info("dictado: transcripción \(tr, format: .fixed(precision: 2))s \(how, privacy: .public), formato \(fm, format: .fixed(precision: 2))s")
    }

    private func record(raw: String, text: String, seconds: Double, ctx: Context, kind: String) {
        let clean = text.trimmingCharacters(in: .whitespaces)
        flow.lastText = clean
        Store.shared.add(Entry(app: ctx.app, category: ctx.category, raw: raw, text: clean,
                               words: clean.split(whereSeparator: \.isWhitespace).count, seconds: seconds, kind: kind, bundle: ctx.bundle))
        if kind == "dictado" && !clean.isEmpty { SupportReminder.shared.recordDictation() }
    }

    // MARK: atajos de portapapeles y transforms

    func pasteLast() {
        guard !flow.lastText.isEmpty else { flow.notice("Todavía no dictaste nada"); return }
        Paster.paste(flow.lastText)
    }

    func copyLast() {
        guard !flow.lastText.isEmpty else { flow.notice("Todavía no dictaste nada"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(flow.lastText, forType: .string)
        flow.notice("Copiado")
    }

    /// Acciones del esquema hablapp:// (ver URLScheme.swift).
    func run(_ link: DeepLink) {
        switch link {
        case .start: if mode == .idle { begin(.handsFree) }
        case .stop: if mode == .handsFree { finish() }
        case .toggle: toggleHandsFree()
        case .cancel: cancel(silent: false)
        case .pasteLast: pasteLast()
        case .transform(let name):
            if let t = Store.shared.transforms.first(where: { Formatter.norm($0.name) == Formatter.norm(name) }) { runTransform(t) }
            else { flow.notice("No existe el transform \(name)") }
        }
    }

    func runTransform(_ t: Transform) {
        guard mode == .idle else { return }
        mode = .busy
        flow.phase = .processing(command: true)
        let context = Ctx.read()
        Task {
            let sel = await Ctx.selection()
            let out = sel.isEmpty ? nil : await Formatter.transform(t, sel, context: context)
            await MainActor.run {
                self.done()
                if sel.isEmpty { Flow.shared.notice("Seleccioná un texto primero"); return }
                guard let out, !out.isEmpty else {
                    Flow.shared.notice(t.createsPrompt ? PromptAPIState.shared.lastError : "No se pudo aplicar el transform. Probá de nuevo")
                    return
                }
                Paster.paste(out)
                self.record(raw: sel, text: out, seconds: 0, ctx: context, kind: "transform")
            }
        }
    }
}
