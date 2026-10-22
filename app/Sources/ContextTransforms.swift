// Transform automático según la app o el servicio abierto en el navegador.
import Cocoa
import SwiftUI
import UniformTypeIdentifiers

enum ContextTransforms {
    struct Target: Identifiable {
        var id: String
        var name: String
    }

    static let suggested = [
        Target(id: "com.openai.chat", name: "ChatGPT"),
        Target(id: "com.openai.codex", name: "Codex"),
        Target(id: "com.anthropic.claudefordesktop", name: "Claude"),
        Target(id: "net.whatsapp.WhatsApp", name: "WhatsApp"),
        Target(id: "web:chatgpt", name: "ChatGPT · navegador"),
        Target(id: "web:claude", name: "Claude · navegador"),
        Target(id: "web:whatsapp", name: "WhatsApp · navegador"),
    ]

    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "com.google.Chrome.beta", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.openai.atlas",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    static func webTarget(_ context: Context) -> String? {
        guard browsers.contains(context.bundle) else { return nil }
        if let url = context.documentURL {
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host?.lowercased() else { return nil }
            for (domain, service) in [("chatgpt.com", "chatgpt"), ("chat.openai.com", "chatgpt"),
                                      ("claude.ai", "claude"), ("web.whatsapp.com", "whatsapp")] {
                if host == domain || host.hasSuffix("." + domain) { return "web:" + service }
            }
            return nil  // Una URL de otro sitio no se reemplaza por una coincidencia del título.
        }
        // Sin URL accesible, sólo títulos con marca completa al principio o al final.
        let matches = ["chatgpt", "claude", "whatsapp"].filter { service in
            let pattern = "^(?:\\(\\d+\\)\\s*)?" + service + "(?:\\s*[-|·:]|$)|(?:^|[-|·])\\s*" + service + "\\s*$"
            return context.title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return matches.count == 1 ? "web:" + matches[0] : nil
    }

    static func resolve(context: Context, rules: [String: String], transforms: [Transform], general: String,
                        enabled: Bool = true) -> Transform? {
        guard enabled else { return nil }
        let id: String
        if let web = webTarget(context), let specific = rules[web] {
            id = specific
        } else if let specific = rules[context.bundle] {
            id = specific
        } else {
            id = general
        }
        return transforms.first { $0.id.uuidString == id }
    }

    static func name(_ id: String) -> String {
        let installed = AppIcon.name(id)
        return installed != id ? installed : (suggested.first { $0.id == id }?.name ?? id)
    }
}

struct ContextTransformsView: View {
    @ObservedObject var store = Store.shared
    private let inherit = "general"

    var configured: [ContextTransforms.Target] {
        store.appTransforms.keys.map { .init(id: $0, name: ContextTransforms.name($0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var candidates: [ContextTransforms.Target] {
        var names = Dictionary(uniqueKeysWithValues: ContextTransforms.suggested.map { ($0.id, ContextTransforms.name($0.id)) })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier {
                names[id] = ContextTransforms.name(id)
            }
        }
        for entry in store.history {
            if let id = entry.bundle, !id.isEmpty, id != Bundle.main.bundleIdentifier, names[id] == nil {
                names[id] = entry.app
            }
        }
        return names.filter { store.appTransforms[$0.key] == nil }
            .map { .init(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transform por app").font(T.sans(15, .semibold)).foregroundStyle(T.text)
                    Text("Elegí cómo se transforma cada dictado según dónde escribas. Se guarda automáticamente.")
                        .font(T.sans(12)).foregroundStyle(T.muted)
                }
                Spacer()
                Menu {
                    ForEach(candidates) { target in
                        Button(target.name) { store.appTransforms[target.id] = "" }
                    }
                    Divider()
                    Button("Elegir otra app…", action: chooseApp)
                } label: {
                    Text("Agregar app").font(T.sans(13, .medium)).foregroundStyle(T.text)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(T.selected, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }

            if configured.isEmpty {
                Text("Agregá ChatGPT o Claude para convertir lo que dictás en un prompt, y WhatsApp para darle otro formato.")
                    .font(T.sans(13)).foregroundStyle(T.muted)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(T.panel, in: RoundedRectangle(cornerRadius: 12))
            } else {
                RowList(items: configured) { target in
                    HStack(spacing: 10) {
                        if let icon = AppIcon.image(target.id) {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: target.id.hasPrefix("web:") ? "globe" : "app")
                                .frame(width: 24).foregroundStyle(T.muted)
                        }
                        Text(target.name).font(T.sans(13, .medium)).foregroundStyle(T.text)
                        Spacer()
                        Picker("Transform para \(target.name)", selection: Binding(
                            get: { store.appTransforms[target.id] ?? inherit },
                            set: { store.appTransforms[target.id] = $0 == inherit ? nil : $0 }
                        )) {
                            Text("Usar el general").tag(inherit)
                            Text("Ninguno").tag("")
                            ForEach(store.transforms) { Text($0.name).tag($0.id.uuidString) }
                            if let id = store.appTransforms[target.id], !id.isEmpty,
                               !store.transforms.contains(where: { $0.id.uuidString == id }) {
                                Text("Transform eliminado (sin aplicar)").tag(id)
                            }
                        }.labelsHidden().frame(width: 220)
                        Button { store.appTransforms[target.id] = nil } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(T.muted).help("Quitar regla y usar el general")
                    }.padding(14)
                }
            }
            Text("La regla de la app reemplaza al transform general. En el navegador, el servicio tiene prioridad: se reconoce por la dirección de la página cuando está disponible o por su nombre en el título de la pestaña. Si no se reconoce, se usa la regla del navegador o el general. «Ninguno» conserva el formato habitual del dictado. Requiere Apple Intelligence.")
                .font(T.sans(12)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Elegí una app para configurar su transform"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let id = Bundle(url: url)?.bundleIdentifier else { return }
            if store.appTransforms[id] == nil { store.appTransforms[id] = "" }
        }
    }
}
