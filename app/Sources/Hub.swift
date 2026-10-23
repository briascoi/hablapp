// La ventana principal (el "Hub"): barra lateral, tarjeta de contenido y ajustes en un modal.

import SwiftUI
import ServiceManagement

enum Page: String, CaseIterable, Identifiable {
    case home, insights, dictionary, snippets, style, transforms, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Dictado"
        case .insights: "Estadísticas"
        case .dictionary: "Diccionario"
        case .snippets: "Snippets"
        case .style: "Estilo"
        case .transforms: "Transforms"
        case .notes: "Notas"
        }
    }
    var icon: String {
        switch self {
        case .home: "mic"
        case .insights: "chart.bar"
        case .dictionary: "book.closed"
        case .snippets: "scissors"
        case .style: "textformat"
        case .transforms: "wand.and.stars"
        case .notes: "note.text"
        }
    }
}

final class HubState: ObservableObject {
    static let shared = HubState()
    @Published var page = Page.home
    @Published var settings = false
    @Published var shortcuts = false
    var settingsAbout = false  // sólo para el snapshot: abrir Ajustes en "Acerca de"
}

struct HubView: View {
    @ObservedObject var hub = HubState.shared
    @AppStorage("theme") var theme = "system"

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(T.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.line))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        UpdateBanner()
                        page
                    }.padding(.horizontal, 40).padding(.vertical, 36).frame(maxWidth: 1000)
                        .frame(maxWidth: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 52).padding(.trailing, 12).padding(.bottom, 12)
        }
        .background(T.bg)
        .overlay(alignment: .topTrailing) { topBar }
        .overlay {
            if hub.settings { SettingsView { hub.settings = false } }
            if hub.shortcuts { ShortcutsView { hub.shortcuts = false } }
        }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 640)
    }

    @ViewBuilder var page: some View {
        switch hub.page {
        case .home: HomePage()
        case .insights: InsightsPage()
        case .dictionary: DictionaryPage()
        case .snippets: SnippetsPage()
        case .style: StylePage()
        case .transforms: TransformsPage()
        case .notes: NotesPage()
        }
    }

    var topBar: some View {
        HStack(spacing: 14) {
            Button {
                theme = (theme == "dark") ? "light" : "dark"
                AppDelegate.applyTheme()
            } label: { Image(systemName: theme == "dark" ? "sun.max" : "moon") }
            Button { hub.shortcuts = true } label: { Image(systemName: "keyboard") }
        }
        .buttonStyle(.plain).font(.system(size: 15)).foregroundStyle(T.text)
        .padding(.top, 16).padding(.trailing, 24)
    }
}

struct Sidebar: View {
    @ObservedObject var hub = HubState.shared
    @ObservedObject var updater = Updater.shared
    @AppStorage("promptAPI.enabled") var promptAPI = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 17, weight: .semibold))
                Text("hablapp").font(T.sans(19, .semibold))
                Chip(text: promptAPI ? "Local + API" : "Local")
            }
            .foregroundStyle(T.text).padding(.leading, 8).padding(.top, 62).padding(.bottom, 20)

            ForEach(Page.allCases) { p in
                item(p.title, p.icon, selected: hub.page == p && !hub.settings) { hub.page = p }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text(promptAPI ? "Audio siempre local" : "Dictado local").font(T.sans(12, .semibold)).foregroundStyle(T.accent)
                Text(promptAPI ? "El texto para mejorar prompts se envía a OpenAI con tu cuenta. Tu audio queda en la Mac." : "Tu voz se transcribe en esta Mac. La mejora de prompts por API es opcional.")
                    .font(T.sans(11)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(T.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.accentSoft))
            .padding(.bottom, 10)
            Divider().overlay(T.line).padding(.bottom, 6)
            item("Ajustes", "gearshape", selected: hub.settings, badge: updater.available != nil) { hub.settings = true }
            item("Atajos", "questionmark.circle", selected: false) { hub.shortcuts = true }
            item("Apoyar el desarrollo", "heart", selected: false) {
                if let url = Links.sponsors { NSWorkspace.shared.open(url) }
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
        .frame(width: 216)
    }

    func item(_ title: String, _ icon: String, selected: Bool, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                if badge { Circle().fill(T.accent).frame(width: 7, height: 7) }
                Spacer()
            }
            .font(T.sans(14)).foregroundStyle(T.text)
            .padding(.horizontal, 8).frame(height: 34)
            .background(selected ? T.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: atajos

struct ShortcutsView: View {
    let onClose: () -> Void
    let rows: [(String, String, [String])] = [
        ("Mantener para hablar", "Mantené y decí algo corto", ["fn"]),
        ("Manos libres", "Doble toque para empezar, otro toque para terminar", ["fn", "fn"]),
        ("Manos libres (alternativo)", "Mientras mantenés fn", ["fn", "espacio"]),
        ("Cancelar", "Descarta el dictado en curso", ["esc"]),
        ("Modo comando", "Seleccioná texto y decí qué hacer con él", ["fn", "⌃ ctrl"]),
        ("Pegar la última transcripción", "Vuelve a pegar lo último que dictaste", ["⌃ ctrl", "⌘ cmd", "V"]),
        ("Copiar la última transcripción", "La deja en el portapapeles", ["⌃ ctrl", "⌘ cmd", "C"]),
        ("Transforms", "Sobre el texto seleccionado", ["⌥ opt", "1…9"]),
    ]
    var body: some View {
        Modal(title: "Atajos", subtitle: "Los atajos que usa hablapp.", width: 560, onClose: onClose) {
            ScrollView { VStack(spacing: 8) {
                ForEach(rows, id: \.0) { title, detail, keys in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(T.sans(13, .medium)).foregroundStyle(T.text)
                            Text(detail).font(T.sans(12)).foregroundStyle(T.muted)
                        }
                        Spacer()
                        HStack(spacing: 4) { ForEach(keys, id: \.self) { Key(text: $0, highlight: $0 == "fn") } }
                            .padding(6).background(T.card, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(12).background(T.panel, in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("URLs para Atajos y Raycast").font(T.sans(13, .medium)).foregroundStyle(T.text)
                    Text("En Atajos usá la acción \"Abrir URLs\"; en Raycast, un Quicklink.").font(T.sans(12)).foregroundStyle(T.muted)
                    ForEach(DeepLink.docs, id: \.0) { url, detail in
                        HStack(spacing: 8) {
                            Text(url).font(.system(size: 12, design: .monospaced)).foregroundStyle(T.text).textSelection(.enabled)
                            Spacer()
                            Text(detail).font(T.sans(12)).foregroundStyle(T.muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(T.panel, in: RoundedRectangle(cornerRadius: 10))
            } }.frame(maxHeight: 520)
            HStack { Spacer(); DarkButton("Listo", action: onClose) }
        }
    }
}

// MARK: ajustes

struct SettingsView: View {
    enum Section: String, CaseIterable { case general = "General", system = "Sistema", promptAPI = "Mejora de prompts", experimental = "Experimental", privacy = "Datos y privacidad", about = "Acerca de" }
    let onClose: () -> Void
    @State var section = HubState.shared.settingsAbout ? Section.about : Section.general

    @AppStorage("userName") var userName = ""
    @AppStorage("mic") var mic = ""
    @AppStorage("language") var language = "es"
    @AppStorage("engine") var engine = "apple"
    @AppStorage("pauseMedia") var pauseMedia = false
    @AppStorage("model") var model = "ggml-small.bin"
    @AppStorage("theme") var theme = "system"
    @AppStorage("showFlowBar") var showFlowBar = true
    @AppStorage("livePreview") var livePreview = true
    @ObservedObject var flow = Flow.shared
    @AppStorage("showInDock") var showInDock = true
    @AppStorage("sounds") var sounds = true
    @AppStorage("mute") var mute = false
    @AppStorage("commandMode") var commandMode = true
    @AppStorage("pressEnter") var pressEnter = false
    @AppStorage("aiFormat") var aiFormat = true
    @AppStorage("screenContext") var screenContext = true
    @AppStorage("historyDays") var historyDays = 0
    @State var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State var confirmClear = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture(perform: onClose)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AJUSTES").font(T.sans(11, .medium)).foregroundStyle(T.muted).padding(.bottom, 8).padding(.leading, 8)
                    ForEach(Section.allCases, id: \.self) { s in
                        Button { section = s } label: {
                            HStack(spacing: 8) {
                                Image(systemName: icon(s)).frame(width: 16)
                                Text(s.rawValue)
                                Spacer()
                            }
                            .font(T.sans(13)).foregroundStyle(T.text).padding(.horizontal, 8).frame(height: 30)
                            .background(section == s ? T.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Text("hablapp v\(AppInfo.version)").font(T.sans(11)).foregroundStyle(T.muted).padding(.leading, 8)
                }
                .padding(14).frame(width: 210).background(T.bg)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(section.rawValue).font(T.serif(24)).foregroundStyle(T.text)
                            Spacer()
                            Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(T.muted) }
                                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                        }
                        content
                    }.padding(28)
                }
                .frame(maxWidth: .infinity)
                .background(T.card)
            }
            .frame(width: 780, height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.22), radius: 30, y: 10)
        }
    }

    func icon(_ s: Section) -> String {
        switch s {
        case .general: "slider.horizontal.3"
        case .system: "laptopcomputer"
        case .promptAPI: "wand.and.stars"
        case .experimental: "flask"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }

    @ViewBuilder var content: some View {
        switch section {
        case .general:
            Group_ {
                Row("Atajos", "Mantené fn y hablá. Doble toque para manos libres.") {
                    SoftButton("Ver") { HubState.shared.settings = false; HubState.shared.shortcuts = true }
                }
                Row("Micrófono", mic.isEmpty ? "Automático (el del sistema)" : (Mics.list().first { $0.id == mic }?.name ?? "No conectado")) {
                    Picker("", selection: $mic) {
                        Text("Automático").tag("")
                        ForEach(Mics.list()) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(width: 200, alignment: .trailing)
                }
                Row("Idioma", "El idioma en el que dictás") {
                    Picker("", selection: $language) {
                        Text("Español").tag("es"); Text("Inglés").tag("en"); Text("Detectar solo").tag("auto")
                    }.labelsHidden().frame(width: 200, alignment: .trailing)
                }
                Row("Motor de transcripción", Transcriber.whisperAvailable ? "Apple usa el modelo de voz del sistema" : "whisper.cpp: no instalado") {
                    Picker("", selection: $engine) {
                        Text("Apple (recomendado)").tag("apple")
                        Text("whisper.cpp").tag("whisper").disabled(!Transcriber.whisperAvailable)
                    }.labelsHidden().frame(width: 200, alignment: .trailing)
                }
                if engine == "whisper" {
                    Row("Modelo de transcripción", "Más grande es más preciso y más lento") {
                        Picker("", selection: $model) {
                            ForEach(models(), id: \.self) { Text($0.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "")).tag($0) }
                        }.labelsHidden().frame(width: 200, alignment: .trailing)
                    }
                }
                Row("Tu nombre", "Para el saludo del inicio") {
                    TextField(NSFullUserName().components(separatedBy: " ").first ?? "", text: $userName)
                        .textFieldStyle(.roundedBorder).frame(width: 200)
                }
                Row("Tema", "") {
                    Picker("", selection: $theme) {
                        Text("Sistema").tag("system"); Text("Claro").tag("light"); Text("Oscuro").tag("dark")
                    }.labelsHidden().frame(width: 200, alignment: .trailing).onChange(of: theme) { AppDelegate.applyTheme() }
                }
            }
        case .system:
            Text("App").font(T.sans(13, .semibold)).foregroundStyle(T.text)
            Group_ {
                Toggler("Abrir al iniciar sesión", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
                Toggler("Mostrar la barra flotante siempre", isOn: $showFlowBar)
                Toggler("Mostrar el texto mientras hablás", detail: "Con el motor de Apple, en la barra flotante", isOn: $livePreview)
                Toggler("Mostrar en el Dock", isOn: $showInDock).onChange(of: showInDock) { AppDelegate.applyDock() }
            }
            Text("Sonido").font(T.sans(13, .semibold)).foregroundStyle(T.text)
            Group_ {
                Toggler("Sonidos de dictado", isOn: $sounds)
                Toggler("Silenciar el audio mientras dictás", isOn: $mute)
                Toggler("Pausar la música mientras dictás", detail: "Music y Spotify; se reanudan al terminar", isOn: $pauseMedia)
            }
        case .experimental:
            Group_ {
                Toggler("Formato con IA", detail: "Puntuación, muletillas y estilo con Apple Intelligence. Estado: \(LLM.status)", isOn: $aiFormat)
                Toggler("Modo comando", detail: "fn + ctrl: seleccioná texto y decí qué hacer con él", isOn: $commandMode)
                Toggler("Comando \"presioná enter\"", detail: "Si terminás el dictado con \"presioná enter\", lo envía", isOn: $pressEnter)
                Row("Último dictado", flow.lastTiming.isEmpty ? "Todavía no dictaste nada" : flow.lastTiming) { EmptyView() }
            }
        case .promptAPI:
            PromptAPISettings()
        case .about:
            AboutSection()
        case .privacy:
            Group_ {
                Row("Dónde se procesa tu voz", "El audio se transcribe en esta Mac. El formato habitual usa Apple Intelligence. Si activas la mejora de prompts por API, ese texto y las instrucciones del transform se envían a OpenAI con tu cuenta.") { EmptyView() }
                Toggler("Usar el texto de la ventana activa", detail: "Ayuda a reconocer nombres y términos. Lectura local mediante Accesibilidad, sin capturas ni guardar el contexto en el historial.", isOn: $screenContext)
                Row("Guardar historial", "Las estadísticas se guardan igual") {
                    Picker("", selection: $historyDays) {
                        Text("Siempre").tag(0); Text("30 días").tag(30); Text("7 días").tag(7); Text("No guardar").tag(-1)
                    }.labelsHidden().frame(width: 160).onChange(of: historyDays) { Store.shared.prune() }
                }
                Row("Tus datos", "Historial, diccionario, snippets y notas en JSON") {
                    SoftButton("Abrir carpeta") { NSWorkspace.shared.open(Store.shared.dir) }
                }
                Row("Borrar historial", "No se puede deshacer") {
                    SoftButton(confirmClear ? "¿Seguro? Borrar" : "Borrar") {
                        if confirmClear { Store.shared.history.removeAll(); confirmClear = false } else { confirmClear = true }
                    }
                }
            }
        }
    }

    func models() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Transcriber.modelsDir().path)) ?? []
        let list = files.filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }.sorted()
        return list.isEmpty ? [model] : list
    }
}

// Panel gris con filas separadas, como los de Ajustes.
struct Group_<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(T.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Row<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing
    init(_ title: String, _ detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(T.sans(13, .medium)).foregroundStyle(T.text)
                if !detail.isEmpty {
                    Text(detail).font(T.sans(12)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider().overlay(T.line).padding(.horizontal, 14) }
    }
}

struct Toggler: View {
    let title: String
    var detail = ""
    @Binding var isOn: Bool
    init(_ title: String, detail: String = "", isOn: Binding<Bool>) { self.title = title; self.detail = detail; _isOn = isOn }
    var body: some View {
        Row(title, detail) { Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(T.button) }
    }
}
