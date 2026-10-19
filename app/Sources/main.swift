// Arranque: menú, ícono en la barra de menús, ventana del hub, barra flotante y motor de atajos.

import Cocoa
import SwiftUI

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
    let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task {
        do { print(try await Transcriber.transcribe(wav: url)); exit(0) }
        catch { print("Error: \(error.localizedDescription)"); exit(1) }
    }
    app.run()
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
