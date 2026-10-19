// Bienvenida paso a paso: micrófono, accesibilidad y un primer dictado de prueba.
// Ventana chica y flotante para que quede visible al lado de Ajustes del Sistema.

import SwiftUI
import AVFoundation
import Combine

final class Onboarding {
    static let shared = Onboarding()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.level = .floating  // Ajustes del Sistema no la tapa
            w.contentView = NSHostingView(rootView: OnboardingView())
            // A la izquierda de la pantalla: Ajustes del Sistema suele abrirse al centro.
            if let vf = NSScreen.main?.visibleFrame {
                w.setFrameOrigin(NSPoint(x: vf.minX + 40, y: vf.midY - 300))
            }
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, mic, accessibility, test, done }

    @ObservedObject var perms = Perms.shared
    @ObservedObject var flow = Flow.shared
    @AppStorage("onboarded") var onboarded = false
    @State var step = Step.welcome
    @State var askedAX = false
    @State var trouble = false
    @State var testText = ""
    @State var downloading = false
    var preview = false  // capturas: sin sondeo de permisos

    init(start: Step = .welcome, preview: Bool = false) {
        _step = State(initialValue: start)
        self.preview = preview
    }

    let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress.padding(.top, 44)
            Group {
                switch step {
                case .welcome: welcome
                case .mic: mic
                case .accessibility: accessibility
                case .test: test
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 28)
        }
        .padding(.horizontal, 36).padding(.bottom, 30)
        .background(T.card)
        .ignoresSafeArea()
        .frame(width: 500, height: 600)
        .onReceive(tick) { _ in poll() }
        .onAppear { poll() }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // Cuando un permiso aparece, avanza solo.
    func poll() {
        guard !preview else { return }
        perms.refresh()
        if perms.accessibility { Engine.shared.ensureTap() }
        if step == .mic, perms.mic { step = .accessibility }
        if step == .accessibility, perms.accessibility { step = .test }
    }

    var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.dropLast(), id: \.self) { s in
                Capsule().fill(s.rawValue <= step.rawValue ? T.accent : T.line).frame(height: 4)
            }
        }
    }

    func header(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(T.serif(30)).foregroundStyle(T.text)
            Text(text).font(T.sans(14)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: pasos

    var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Hablá en cualquier app", "Mantené fn, hablá y soltá: el texto aparece donde está el cursor, con puntuación y en el tono de cada app. Todo se procesa en tu Mac.")
            HStack(spacing: 10) {
                Key(text: "fn", highlight: true).scaleEffect(1.6).frame(width: 44)
                Image(systemName: "arrow.right").foregroundStyle(T.muted)
                Wave(levels: [0.3, 0.6, 0.9, 0.5, 1, 0.7, 0.4, 0.8, 0.5, 0.3, 0.2], color: T.text)
                Image(systemName: "arrow.right").foregroundStyle(T.muted)
                Text("Texto listo").font(T.sans(13, .medium)).foregroundStyle(T.text)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(T.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.vertical, 10)
            Text("Para eso necesita dos permisos. Te llevo paso a paso, toma un minuto.")
                .font(T.sans(14)).foregroundStyle(T.text)
            Spacer()
            HStack { Spacer(); DarkButton("Empezar") { step = perms.mic ? (perms.accessibility ? .test : .accessibility) : .mic } }
        }
    }

    var mic: some View {
        VStack(alignment: .leading, spacing: 22) {
            header("Micrófono", "hablapp sólo escucha mientras mantenés fn o tenés activo el manos libres. El audio no sale de tu Mac.")
            status(perms.mic, "Micrófono permitido", "Esperando el permiso…")
            if AVPermission.denied {
                Text("Lo habías rechazado antes. Se abrió Ajustes: activá hablapp en la lista de Micrófono.")
                    .font(T.sans(13)).foregroundStyle(T.text)
            }
            Spacer()
            HStack { Spacer(); DarkButton("Permitir micrófono") { perms.requestMic() } }
        }
    }

    var accessibility: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Accesibilidad", "Con este permiso hablapp detecta la tecla fn, lee el texto alrededor del cursor y pega lo que dictás.")
            VStack(alignment: .leading, spacing: 12) {
                instruction(1, askedAX ? "Si no se abrió Ajustes, tocá «Abrir Ajustes» de nuevo."
                               : "Tocá «Abrir Ajustes». Si aparece un aviso de macOS, elegí «Abrir Ajustes del Sistema».")
                instruction(2, "En Privacidad y seguridad › Accesibilidad, activá el interruptor de hablapp.")
                instruction(3, "Si hablapp no está en la lista, arrastrá este ícono adentro:")
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                        .help("Arrastralo a la lista de Accesibilidad")
                    Text("hablapp").font(T.sans(14, .medium)).foregroundStyle(T.text)
                    Spacer()
                    Toggle("", isOn: .constant(true)).toggleStyle(.switch).labelsHidden().allowsHitTesting(false)
                }
                .padding(12).background(T.panel, in: RoundedRectangle(cornerRadius: 10))
                .padding(.leading, 30)
            }
            status(perms.accessibility, "Accesibilidad permitida", "Esperando el permiso… avanzo solo cuando lo actives.")
            if askedAX { troubleshooting }
            Spacer(minLength: 0)
            HStack { Spacer(); DarkButton("Abrir Ajustes", action: openAX) }
        }
    }

    var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { trouble.toggle() } label: {
                Label("¿Ya está activado y no avanza?", systemImage: trouble ? "chevron.down" : "chevron.right")
                    .font(T.sans(12, .medium)).foregroundStyle(T.muted)
            }.buttonStyle(.plain)
            if trouble {
                Text("Pasa cuando quedó una versión vieja de hablapp en la lista. Restablecé el permiso y activalo de nuevo; si sigue igual, reiniciá la app.")
                    .font(T.sans(12)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    SoftButton("Restablecer permiso") { Perms.shared.resetAccessibility(); openAX() }
                    SoftButton("Reiniciar hablapp") { AppDelegate.relaunch() }
                }
            }
        }
    }

    var test: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Probalo", "Hacé clic en el cuadro, mantené fn, decí una frase y soltá.")
            TextEditor(text: $testText)
                .font(T.sans(15)).scrollContentBackground(.hidden)
                .padding(12).frame(height: 140)
                .background(T.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if testText.isEmpty {
                        Text("Por ejemplo: «hola, estoy probando hablapp»").font(T.sans(15)).foregroundStyle(T.muted)
                            .padding(17).allowsHitTesting(false)
                    }
                }
            if downloading {
                Label("Descargando el modelo de voz de Apple…", systemImage: "arrow.down.circle").font(T.sans(13)).foregroundStyle(T.accent)
            } else if case .recording = flow.phase {
                Label("Te estoy escuchando…", systemImage: "waveform").font(T.sans(13)).foregroundStyle(T.accent)
            } else if case .processing = flow.phase {
                Label("Escribiendo…", systemImage: "ellipsis").font(T.sans(13)).foregroundStyle(T.accent)
            } else if !testText.isEmpty {
                status(true, "¡Funciona!", "")
            }
            Spacer()
            .task(id: step) { await prepareModel() }
            HStack {
                Button("Saltear") { step = .done }.buttonStyle(.plain).font(T.sans(13)).foregroundStyle(T.muted)
                Spacer()
                DarkButton("Seguir") { step = .done }
            }
        }
    }

    /// Con el motor Apple, baja el modelo del idioma al llegar al dictado de prueba (lo instala macOS).
    func prepareModel() async {
        guard step == .test, !preview, Transcriber.engine == "apple", !(await Transcriber.appleModelInstalled()) else { return }
        downloading = true
        try? await Transcriber.ensureAppleModel()
        downloading = false
    }

    var done: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("¡Listo!", "Ya podés dictar en cualquier app. Algunos atajos para arrancar:")
            VStack(alignment: .leading, spacing: 12) {
                shortcut(["fn"], "Mantener para dictar")
                shortcut(["fn", "fn"], "Doble toque: manos libres")
                shortcut(["fn", "⌃"], "Modo comando: pedile algo a la IA")
                shortcut(["⌃", "⌘", "V"], "Pegar la última transcripción")
                shortcut(["esc"], "Cancelar")
            }
            Spacer()
            HStack {
                Spacer()
                DarkButton("Abrir hablapp") {
                    onboarded = true
                    Onboarding.shared.close()
                    AppDelegate.shared?.showHub()
                }
            }
        }
    }

    // MARK: piezas

    func instruction(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(T.sans(12, .semibold)).foregroundStyle(T.accent)
                .frame(width: 20, height: 20).background(T.accentSoft, in: Circle())
            Text(text).font(T.sans(13)).foregroundStyle(T.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    func status(_ ok: Bool, _ yes: String, _ no: String) -> some View {
        HStack(spacing: 8) {
            if ok {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(T.teal)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(ok ? yes : no).font(T.sans(13, .medium)).foregroundStyle(ok ? T.teal : T.muted)
        }
    }

    func shortcut(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { Key(text: $0.element, highlight: $0.element == "fn") }
            Text(text).font(T.sans(13)).foregroundStyle(T.text).padding(.leading, 8)
        }
    }

    func openAX() {
        askedAX = true
        Perms.shared.requestAccessibility()
    }
}

enum AVPermission {
    static var denied: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .denied }
}
