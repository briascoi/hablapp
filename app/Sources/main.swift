// Arranque: menú, ícono en la barra de menús, ventana del hub, barra flotante y motor de atajos.

import Cocoa
import SwiftUI
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?
    private var window: NSWindow?
    private var status: NSStatusItem?
    private var bar: FlowBar?

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        Self.applyDock()
        Self.applyTheme()
        buildMenu()
        buildStatusItem()
        bar = FlowBar()
        Engine.shared.start()
        Perms.shared.refresh()
        Updater.shared.startAutomatic()
        if !UserDefaults.standard.bool(forKey: "onboarded") || !Perms.shared.allGood { Onboarding.shared.show() }
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        let links = urls.compactMap(DeepLink.parse)
        guard !links.isEmpty else { return }
        // Si el hub no está a la vista devolvemos el foco a la app anterior, para leer su contexto y no el nuestro.
        if window?.isVisible != true { NSApp.hide(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { links.forEach(Engine.shared.run) }
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showHub()
        return true
    }

    @objc func showHub() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 980, height: 640)
            w.contentView = NSHostingView(rootView: HubView())
            w.setFrameAutosaveName("hub")
            if w.frame.origin == .zero { w.center() }
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Abre una instancia nueva y cierra esta: algunos cambios de permisos recién se ven al reiniciar.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func applyTheme() {
        switch UserDefaults.standard.string(forKey: "theme") ?? "system" {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static func applyDock() {
        let dock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
    }

    // MARK: menús

    private func buildMenu() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Acerca de hablapp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(withTitle: "Buscar actualizaciones…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Ocultar hablapp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Salir de hablapp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edición", action: nil, keyEquivalent: "").submenu = edit

        let win = NSMenu(title: "Ventana")
        win.addItem(withTitle: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Ventana", action: nil, keyEquivalent: "").submenu = win
        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "hablapp")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        status = item
    }

    // El menú se arma al abrirse, así la lista de micrófonos está al día.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Abrir hablapp", action: #selector(showHub), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pegar última transcripción", action: #selector(pasteLast), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let mics = NSMenu()
        let current = UserDefaults.standard.string(forKey: "mic") ?? ""
        let def = mics.addItem(withTitle: "Predeterminado del sistema", action: #selector(pickMic(_:)), keyEquivalent: "")
        def.target = self
        def.representedObject = ""
        def.state = current.isEmpty ? .on : .off
        for m in Mics.list() {
            let i = mics.addItem(withTitle: m.name, action: #selector(pickMic(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = m.id
            i.state = m.id == current ? .on : .off
        }
        menu.addItem(withTitle: "Micrófono", action: nil, keyEquivalent: "").submenu = mics
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: "").target = self
        if let r = Updater.shared.available {
            menu.addItem(withTitle: "Actualizar a \(r.version)…", action: #selector(installUpdate), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Buscar actualizaciones…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    @objc private func pasteLast() { Engine.shared.pasteLast() }
    @objc private func pickMic(_ sender: NSMenuItem) { UserDefaults.standard.set(sender.representedObject as? String ?? "", forKey: "mic") }
    @objc private func checkUpdates() { Updater.shared.check(userInitiated: true) }
    @objc private func installUpdate() { if let r = Updater.shared.available { Updater.shared.install(r) } }
    @objc private func openSettings() { showHub(); HubState.shared.settings = true }
}

// Modo de prueba: `hablapp --snapshot <carpeta>` dibuja cada pantalla en PNG fuera de pantalla y sale.
func snapshot(_ dir: String) {
    let w = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 1180, height: 820), styleMask: [.titled, .fullSizeContentView],
                     backing: .buffered, defer: false)
    w.titlebarAppearsTransparent = true
    let host = NSHostingView(rootView: HubView())
    w.contentView = host
    w.orderFrontRegardless()
    let hub = HubState.shared
    let shots: [(String, () -> Void)] = Page.allCases.map { p in (p.rawValue, { hub.page = p }) }
        + [("settings", { hub.page = .home; hub.settings = true }), ("shortcuts", { hub.settings = false; hub.shortcuts = true }),
              ("about", { hub.shortcuts = false; hub.settingsAbout = true; hub.settings = true })]
    for (name, setup) in shots {
        setup()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    // Barra flotante grabando, con texto en vivo, sobre fondo claro y oscuro.
    Flow.shared.phase = .recording(handsFree: true, command: false)
    Flow.shared.levels = [0.2, 0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 0.4, 0.5, 0.3, 0.2]
    Flow.shared.partial = "Hola, te escribo para confirmar la reunión del jueves a las 5 de la tarde en la oficina de Palermo"
    for (name, bg) in [("flowbar-light", NSColor.white), ("flowbar-dark", NSColor.darkGray)] {
        let v = NSHostingView(rootView: FlowBarView().background(Color(nsColor: bg)))
        v.frame = NSRect(x: 0, y: 0, width: 400, height: 104)
        w.setContentSize(v.frame.size)
        w.contentView = v
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    Flow.shared.phase = .idle
    for s in OnboardingView.Step.allCases {
        let v = NSHostingView(rootView: OnboardingView(start: s, preview: true))
        v.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        w.setContentSize(v.frame.size)
        w.contentView = v
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/onb-\(s.rawValue).png"))
    }
}

// Pruebas rápidas: `hablapp --selftest`. Sin XCTest; usan check() porque assert se elimina con -O.
// Los paquetes siguientes agregan sus casos al final de esta función.
func selfTest() {
    var fails = 0
    func check(_ name: String, _ ok: Bool) { print(ok ? "ok    " : "FALLA ", name); if !ok { fails += 1 } }

    // Comparación de versiones del actualizador
    check("0.10.0 es más nueva que 0.9.1", Updater.newer("0.10.0", than: "0.9.1"))
    check("0.2.0 no es más nueva que 0.2.0", !Updater.newer("0.2.0", than: "0.2.0"))
    check("0.2.0 no es más nueva que 0.2.1", !Updater.newer("0.2.0", than: "0.2.1"))

    // Verificación de firma: la propia app pasa, una app de Apple no, y una "actualización" igual a la actual tampoco
    check("firma: la propia app pasa", (try? Updater.verifySignature(Bundle.main.bundleURL)) != nil)
    check("firma: Calculator.app falla", (try? Updater.verifySignature(URL(fileURLWithPath: "/System/Applications/Calculator.app"))) == nil)
    check("update: misma versión se rechaza", (try? Updater.verifyUpdate(Bundle.main.bundleURL)) == nil)

    // Diccionario que aprende (Learner.corrections)
    func pairs(_ p: String, _ f: String) -> String { Learner.corrections(pasted: p, field: f).map { "\($0.0)>\($0.1)" }.joined(separator: ",") }
    check("learner: cloud code -> Claude Code", pairs("hola cloud code", "hola Claude Code") == "cloud>Claude,code>Code")
    check("learner: campo con texto antes y después", pairs("hola cloud code", "ayer hablé. hola Claude Code mañana") == "cloud>Claude,code>Code")
    check("learner: sin cambios", pairs("hola cloud code", "hola cloud code").isEmpty)
    check("learner: puntuación no cuenta", pairs("hola cloud code.", "hola, cloud code!").isEmpty)
    check("learner: reescritura total se ignora", pairs("hola cloud code", "chau mundo cruel").isEmpty)
    check("learner: números se ignoran", pairs("llego a las 5 hoy", "llego a las 6 hoy").isEmpty)
    check("learner: nombre propio con mayúscula", pairs("avisale a juan hoy", "avisale a Fernando hoy") == "juan>Fernando")
    check("learner: palabra común distinta se ignora", pairs("avisale a juan hoy", "avisale a mañana hoy").isEmpty)
    check("learner: una sola palabra no aprende", pairs("cloud", "Claude").isEmpty)

    // Esquema hablapp://
    func link(_ s: String) -> DeepLink? { URL(string: s).flatMap(DeepLink.parse) }
    check("url: start", link("hablapp://start") == .start)
    check("url: stop", link("hablapp://stop") == .stop)
    check("url: toggle", link("hablapp://toggle") == .toggle)
    check("url: cancel", link("hablapp://cancel") == .cancel)
    check("url: paste-last", link("hablapp://paste-last") == .pasteLast)
    check("url: ruta con barra", link("hablapp:///start") == .start)
    check("url: transform", link("hablapp://transform?name=Pulir") == .transform("Pulir"))
    check("url: transform con espacios y tildes", link("hablapp://transform?name=Al%20ingl%C3%A9s") == .transform("Al inglés"))
    check("url: transform sin nombre", link("hablapp://transform") == nil)
    check("url: ruta desconocida", link("hablapp://nada") == nil)
    check("url: otro esquema", link("https://start") == nil)

    // Selección contextual: servicio web > app > general; vacío desactiva sólo el transform.
    let general = Transform(name: "General", prompt: "general")
    let prompt = Transform(name: "Prompt", prompt: "prompt")
    let message = Transform(name: "Mensaje", prompt: "mensaje")
    let transforms = [general, prompt, message]
    var ctx = Context()
    ctx.bundle = "com.google.Chrome"
    ctx.title = "Proyecto nuevo - ChatGPT"
    let rules = ["web:chatgpt": prompt.id.uuidString, ctx.bundle: message.id.uuidString]
    func resolved(_ c: Context, _ r: [String: String]) -> Transform? {
        ContextTransforms.resolve(context: c, rules: r, transforms: transforms, general: general.id.uuidString)
    }
    check("contexto: servicio web gana al navegador", resolved(ctx, rules) == prompt)
    check("contexto: ninguno web bloquea app y general", resolved(ctx, ["web:chatgpt": "", ctx.bundle: message.id.uuidString]) == nil)
    check("contexto: sin regla web usa navegador", resolved(ctx, [ctx.bundle: message.id.uuidString]) == message)
    check("contexto: sin reglas usa general", resolved(ctx, [:]) == general)
    ctx.title = "Documento de trabajo"
    check("contexto: otra pestaña no usa regla de ChatGPT", resolved(ctx, rules) == message)
    ctx.bundle = "com.apple.TextEdit"
    ctx.title = "Notas sobre ChatGPT"
    check("contexto: título de otra app no es un servicio web", ContextTransforms.webTarget(ctx) == nil)
    ctx.bundle = "com.anthropic.claudefordesktop"
    check("contexto: Claude nativo", resolved(ctx, [ctx.bundle: prompt.id.uuidString]) == prompt)
    check("contexto: ninguno nativo bloquea general", resolved(ctx, [ctx.bundle: ""]) == nil)
    check("contexto: transform eliminado no ejecuta otro", resolved(ctx, [ctx.bundle: UUID().uuidString]) == nil)
    ctx.bundle = "com.apple.Safari"
    ctx.title = "(2) WhatsApp"
    check("contexto: WhatsApp web", ContextTransforms.webTarget(ctx) == "web:whatsapp")
    ctx.title = "Claude | Proyecto"
    check("contexto: Claude web", ContextTransforms.webTarget(ctx) == "web:claude")
    ctx.title = "Claudette"
    check("contexto: no coincide nombre parcial", ContextTransforms.webTarget(ctx) == nil)
    ctx.title = "¿Cómo usar ChatGPT? - Buscador"
    check("contexto: mención en otra página no activa ChatGPT", ContextTransforms.webTarget(ctx) == nil)
    ctx.title = "Claude - ChatGPT"
    check("contexto: título ambiguo no activa un servicio", ContextTransforms.webTarget(ctx) == nil)
    ctx.title = "Título de conversación sin marca"
    ctx.documentURL = URL(string: "https://chatgpt.com/c/123")
    check("contexto: URL reconoce ChatGPT sin marca en título", ContextTransforms.webTarget(ctx) == "web:chatgpt")
    check("contexto: regla web por URL tiene prioridad", resolved(ctx, rules) == prompt)
    ctx.documentURL = URL(string: "https://claude.ai/chat/123")
    check("contexto: Claude por URL", ContextTransforms.webTarget(ctx) == "web:claude")
    ctx.documentURL = URL(string: "https://web.whatsapp.com/")
    check("contexto: WhatsApp por URL", ContextTransforms.webTarget(ctx) == "web:whatsapp")
    ctx.documentURL = URL(string: "https://chat.openai.com/")
    check("contexto: dominio anterior de ChatGPT", ContextTransforms.webTarget(ctx) == "web:chatgpt")
    ctx.title = "ChatGPT"
    ctx.documentURL = URL(string: "https://example.com/chatgpt")
    check("contexto: URL ajena gana a título coincidente", ContextTransforms.webTarget(ctx) == nil)
    ctx.documentURL = URL(string: "https://chatgpt.com.example.com/")
    check("contexto: dominio parecido no coincide", ContextTransforms.webTarget(ctx) == nil)
    ctx.documentURL = URL(string: "file:///tmp/chatgpt.html")
    check("contexto: documento local no es ChatGPT web", ContextTransforms.webTarget(ctx) == nil)
    ctx.documentURL = URL(string: "https://chatgpt.com/")
    check("contexto: interruptor desactiva todos los transforms",
          ContextTransforms.resolve(context: ctx, rules: rules, transforms: transforms,
                                    general: general.id.uuidString, enabled: false) == nil)
    ctx.bundle = "com.openai.chat"
    ctx.documentURL = nil
    check("contexto: ChatGPT nativo", resolved(ctx, [ctx.bundle: prompt.id.uuidString]) == prompt)
    ctx.bundle = "com.openai.codex"
    check("contexto: ChatGPT y Codex con bundle actual", resolved(ctx, [ctx.bundle: prompt.id.uuidString]) == prompt)
    ctx.bundle = "net.whatsapp.WhatsApp"
    check("contexto: WhatsApp nativo", resolved(ctx, [ctx.bundle: message.id.uuidString]) == message)
    check("contexto: sin general ni regla no transforma",
          ContextTransforms.resolve(context: ctx, rules: [:], transforms: transforms, general: "") == nil)

    // Persistencia y borrado en datos y preferencias temporales, sin tocar la configuración del usuario.
    let testID = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hablapp-selftest-" + testID)
    let suite = "hablapp-selftest-" + testID
    let preferences = UserDefaults(suiteName: suite)!
    do {
        defer {
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        let store = Store(directory: directory, preferences: preferences)
        check("contexto: instalación anterior sin archivo conserva reglas vacías", store.appTransforms.isEmpty)
        store.transforms = transforms
        store.appTransforms = ["com.openai.chat": prompt.id.uuidString, "web:claude": prompt.id.uuidString,
                               "net.whatsapp.WhatsApp": ""]
        preferences.set(prompt.id.uuidString, forKey: "autoTransform")
        let reopened = Store(directory: directory, preferences: preferences)
        check("contexto: reglas persisten al reabrir", reopened.appTransforms == store.appTransforms)
        check("contexto: transforms conservan sus IDs al reabrir", reopened.transforms == transforms)
        store.transforms.removeAll { $0.id == prompt.id }
        check("contexto: borrar transform desactiva reglas que lo usaban",
              store.appTransforms["com.openai.chat"] == "" && store.appTransforms["web:claude"] == "")
        check("contexto: borrar transform limpia el general", preferences.string(forKey: "autoTransform") == nil)
        check("contexto: borrar transform respeta regla Ninguno", store.appTransforms["net.whatsapp.WhatsApp"] == "")
        let cleaned = Store(directory: directory, preferences: preferences)
        check("contexto: limpieza persiste al reabrir", cleaned.appTransforms == store.appTransforms)
        store.appTransforms["com.openai.chat"] = nil
        check("contexto: quitar regla persiste herencia del general",
              Store(directory: directory, preferences: preferences).appTransforms["com.openai.chat"] == nil)
    }

    print(fails == 0 ? "selftest OK" : "selftest: \(fails) fallas")
    exit(fails == 0 ? 0 : 1)
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--selftest") { selfTest() }
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    app.setActivationPolicy(.accessory)
    snapshot(CommandLine.arguments[i + 1])
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--transcribe"), i + 1 < CommandLine.arguments.count {
    // Depuración: transcribe un WAV con el motor elegido, imprime el texto y sale.
    // Con --live lo pasa en tramos de 0,1 s por la transcripción en vivo (WAV de 16 kHz mono Int16) y mide el cierre.
    let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task {
        do {
            if CommandLine.arguments.contains("--live") {
                let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
                let live = LiveTranscription()
                live.onText = { print("…", $0) }
                live.start()
                while let b = AVAudioPCMBuffer(pcmFormat: Recorder.format, frameCapacity: 1600), (try? file.read(into: b)) != nil, b.frameLength > 0 {
                    live.feed(b)
                    try await Task.sleep(for: .milliseconds(100))
                }
                let t0 = Date()
                let text = try await live.finish()
                print(text, String(format: "\n(cierre: %.2f s)", Date().timeIntervalSince(t0)))
            } else {
                print(try await Transcriber.transcribe(wav: url))
            }
            exit(0)
        }
        catch { print("Error: \(error.localizedDescription)"); exit(1) }
    }
    app.run()
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
