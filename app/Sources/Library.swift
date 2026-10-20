// Diccionario, Snippets, Estilo, Transforms y Notas.

import SwiftUI

// MARK: Diccionario

struct DictionaryPage: View {
    enum Filter { case all, words, replacements }
    @ObservedObject var store = Store.shared
    @State var filter = Filter.all
    @State var query = ""
    @State var editing: Word?

    var items: [Word] {
        store.words.filter {
            switch filter {
            case .all: true
            case .words: !$0.isReplacement
            case .replacements: $0.isReplacement
            }
        }
        .filter { query.isEmpty || ($0.from + " " + $0.to).localizedCaseInsensitiveContains(query) }
        .sorted { $0.from.localizedCaseInsensitiveCompare($1.from) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Diccionario") { DarkButton("Agregar") { editing = Word() } }
            Tabs(tabs: [(Filter.all, "Todo"), (.words, "Palabras"), (.replacements, "Reemplazos")], selection: $filter)
            if !store.suggestions.isEmpty { SuggestionsList() }
            Hero(title: "hablapp escribe como vos.",
                 subtitle: "Sumá nombres propios, siglas y términos de tu rubro para que se transcriban bien. Con un reemplazo, una frase dicha se convierte en otra.") {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { HeroChip(text: $0) }
                }
            }
            HStack { Spacer(); SearchField(text: $query) }
            if items.isEmpty {
                Text(store.words.isEmpty ? "Tu diccionario está vacío. Agregá la primera palabra." : "Sin resultados.")
                    .font(T.sans(14)).foregroundStyle(T.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                RowList(items: items) { w in
                    EditableRow(onEdit: { editing = w }, onDelete: { store.words.removeAll { $0.id == w.id } }) {
                        HStack(spacing: 8) {
                            Text(w.from).font(T.sans(14)).foregroundStyle(T.text)
                            if w.isReplacement {
                                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(T.muted)
                                Text(w.to).font(T.sans(14)).foregroundStyle(T.text)
                            }
                        }
                    }
                }
            }
        }
        .overlay { if let w = editing { WordEditor(word: w) { editing = nil } } }
    }

    var chips: [String] {
        let mine = store.words.prefix(4).map { $0.isReplacement ? "\($0.from) → \($0.to)" : $0.from }
        return mine.isEmpty ? ["hablapp", "Isma", "FoundationModels", "q sé → qué sé yo"] : Array(mine)
    }
}

/// Correcciones que hiciste a mano después de dictar (ver Learner.swift).
struct SuggestionsList: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sugeridas").font(T.sans(15, .semibold)).foregroundStyle(T.text)
            Text("Palabras que corregiste a mano después de dictar. Agregalas y hablapp las escribe bien la próxima vez.")
                .font(T.sans(12)).foregroundStyle(T.muted)
            RowList(items: store.suggestions) { w in
                HStack(spacing: 8) {
                    Text(w.from).font(T.sans(14)).foregroundStyle(T.text)
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(T.muted)
                    Text(w.to).font(T.sans(14)).foregroundStyle(T.text)
                    Spacer()
                    SoftButton("Descartar") { Learner.discard(w) }
                    DarkButton("Agregar") { Learner.accept(w) }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
    }
}

struct WordEditor: View {
    @State var word: Word
    @State var replace: Bool
    let onClose: () -> Void

    init(word: Word, onClose: @escaping () -> Void) {
        _word = State(initialValue: word)
        _replace = State(initialValue: word.isReplacement)
        self.onClose = onClose
    }

    var body: some View {
        Modal(title: word.from.isEmpty ? "Agregar al diccionario" : "Editar", onClose: onClose) {
            Toggle("Reemplazar por otra cosa", isOn: $replace).toggleStyle(.switch).font(T.sans(13))
            Field(label: replace ? "Cuando diga" : "Palabra o frase", text: $word.from)
            if replace { Field(label: "Escribir", text: $word.to) }
            HStack { Spacer(); DarkButton("Guardar", action: save) }
        }
    }

    func save() {
        var w = word
        w.from = w.from.trimmingCharacters(in: .whitespaces)
        w.to = replace ? w.to.trimmingCharacters(in: .whitespaces) : ""
        guard !w.from.isEmpty else { return onClose() }
        let store = Store.shared
        if let i = store.words.firstIndex(where: { $0.id == w.id }) { store.words[i] = w } else { store.words.append(w) }
        onClose()
    }
}

/// Fila con lápiz y tacho que aparecen al pasar el mouse.
struct EditableRow<Content: View>: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content
    @State var hover = false

    var body: some View {
        HStack {
            content
            Spacer()
            if hover {
                HStack(spacing: 12) {
                    Button(action: onEdit) { Image(systemName: "pencil") }.buttonStyle(.plain).help("Editar")
                    Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain).help("Borrar")
                }.font(.system(size: 12)).foregroundStyle(T.muted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(hover ? T.panel.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onEdit)
    }
}

// MARK: Snippets

struct SnippetsPage: View {
    @ObservedObject var store = Store.shared
    @State var query = ""
    @State var editing: Snippet?

    var items: [Snippet] {
        store.snippets.filter { query.isEmpty || ($0.trigger + " " + $0.text).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Snippets") { DarkButton("Agregar") { editing = Snippet() } }
            Hero(title: "Lo que no tenés por qué volver a escribir.",
                 subtitle: "Decí la frase disparadora y hablapp pega el texto completo: tu mail, un link de agenda, una firma.",
                 colors: [Color(hex: 0x2A2F3A), Color(hex: 0x4E5B6E), Color(hex: 0x6E5A48)]) {
                HStack(spacing: 8) {
                    HeroChip(text: "mi mail → isma@…")
                    HeroChip(text: "link de agenda → cal.com/…")
                }
            }
            HStack { Spacer(); SearchField(text: $query) }
            if items.isEmpty {
                Text(store.snippets.isEmpty ? "Todavía no tenés snippets." : "Sin resultados.")
                    .font(T.sans(14)).foregroundStyle(T.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                RowList(items: items) { s in
                    EditableRow(onEdit: { editing = s }, onDelete: { store.snippets.removeAll { $0.id == s.id } }) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(s.trigger).font(T.sans(14, .medium)).foregroundStyle(T.text).frame(width: 180, alignment: .leading)
                            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(T.muted).padding(.top, 3)
                            Text(s.text).font(T.sans(14)).foregroundStyle(T.text).lineLimit(2)
                        }
                    }
                }
            }
        }
        .overlay { if let s = editing { SnippetEditor(snippet: s) { editing = nil } } }
    }
}

struct SnippetEditor: View {
    @State var snippet: Snippet
    let onClose: () -> Void

    var body: some View {
        Modal(title: snippet.trigger.isEmpty ? "Nuevo snippet" : "Editar snippet",
              subtitle: "Cuando digas la frase, se pega el texto.", onClose: onClose) {
            Field(label: "Frase disparadora", text: $snippet.trigger)
            Field(label: "Texto", text: $snippet.text, multiline: true)
            HStack { Spacer(); DarkButton("Guardar", action: save) }
        }
    }

    func save() {
        snippet.trigger = snippet.trigger.trimmingCharacters(in: .whitespaces)
        guard !snippet.trigger.isEmpty, !snippet.text.isEmpty else { return onClose() }
        let store = Store.shared
        if let i = store.snippets.firstIndex(where: { $0.id == snippet.id }) { store.snippets[i] = snippet }
        else { store.snippets.append(snippet) }
        onClose()
    }
}

// MARK: Estilo

struct StylePage: View {
    @State var category = Category.personal

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Estilo") { EmptyView() }
            Tabs(tabs: Category.allCases.map { ($0, $0.tab) }, selection: $category)
            Hero(title: heroTitle,
                 subtitle: "hablapp detecta la app activa y ajusta mayúsculas y puntuación al tono que elijas.",
                 colors: [Color(hex: 0x3B2D4F), Color(hex: 0x6A4C8C), Color(hex: 0x2F4B4E)]) {
                HStack(spacing: 8) {
                    ForEach(apps, id: \.self) { b in
                        if let icon = AppIcon.image(b) { Image(nsImage: icon).resizable().frame(width: 30, height: 30) }
                    }
                }
            }
            ToneCards(category: category).id(category)
            AppPrompts()
        }
    }

    var heroTitle: String {
        switch category {
        case .personal: "Este estilo se aplica en tus mensajeros personales"
        case .work: "Este estilo se aplica en tus mensajeros de trabajo"
        case .email: "Este estilo se aplica en tus apps de email"
        case .other: "Este estilo se aplica en el resto de las apps"
        }
    }

    var apps: [String] {
        switch category {
        case .personal: Ctx.personalApps
        case .work: Ctx.workApps
        case .email: Ctx.emailApps
        case .other: ["com.apple.Notes", "com.apple.TextEdit", "notion.id", "com.google.Chrome", "com.apple.Safari"]
        }
    }
}

struct ToneCards: View {
    let category: Category
    @AppStorage var tone: String

    init(category: Category) {
        self.category = category
        _tone = AppStorage(wrappedValue: category.defaultTone.rawValue, "style." + category.rawValue)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Tone.allCases) { t in
                let selected = tone == t.rawValue
                Button { tone = t.rawValue } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.title).font(T.serif(24)).foregroundStyle(T.text)
                            Text(t.subtitle).font(T.sans(12)).foregroundStyle(T.muted)
                        }
                        HStack(alignment: .bottom, spacing: 8) {
                            Circle().fill(LinearGradient(colors: [T.accent, T.teal], startPoint: .top, endPoint: .bottom))
                                .frame(width: 26, height: 26)
                                .overlay(Text("I").font(T.sans(12, .semibold)).foregroundStyle(.white))
                            Text(category == .email ? emailSample(t) : t.sample)
                                .font(T.sans(13)).foregroundStyle(T.text).multilineTextAlignment(.leading)
                                .padding(12).background(T.panel, in: RoundedRectangle(cornerRadius: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18).frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                    .background(T.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? T.accent : T.line, lineWidth: selected ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }
    }

    func emailSample(_ t: Tone) -> String {
        switch t {
        case .formal: "Hola Juan:\n\nTe confirmo la reunión del jueves a las 10. Avisame si te queda bien.\n\nSaludos,\nIsma"
        case .casual: "Hola Juan\n\nTe confirmo la reunión del jueves a las 10, avisame si te queda bien\n\nSaludos\nIsma"
        case .veryCasual: "hola juan\n\nte confirmo la reunión del jueves a las 10 avisame si te queda bien\n\nsaludos\nisma"
        }
    }
}

// MARK: instrucciones por app

struct AppPrompts: View {
    @ObservedObject var store = Store.shared
    struct Ref: Identifiable { let id: String; let name: String }

    var configured: [Ref] {
        store.appPrompts.keys.map { Ref(id: $0, name: AppIcon.name($0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Apps donde ya dictaste y todavía no tienen instrucciones.
    var candidates: [Ref] {
        var out: [String: String] = [:]
        for e in store.history where !e.app.isEmpty {
            let b = e.bundle ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == e.app }?.bundleIdentifier
            if let b, store.appPrompts[b] == nil { out[b] = e.app }
        }
        return out.map { Ref(id: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Instrucciones por app").font(T.sans(15, .semibold)).foregroundStyle(T.text)
                    Text("Pedile a hablapp algo extra cuando dictás en una app puntual, por ejemplo \"respondé siempre en inglés\".")
                        .font(T.sans(12)).foregroundStyle(T.muted)
                }
                Spacer()
                Menu {
                    if candidates.isEmpty { Text("Dictá en alguna app para que aparezca acá") }
                    ForEach(candidates) { c in Button(c.name) { store.appPrompts[c.id] = "" } }
                } label: {
                    Text("Agregar app").font(T.sans(13, .medium)).foregroundStyle(T.text)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(T.selected, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            if configured.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "app.badge").font(T.sans(16)).foregroundStyle(T.muted)
                    Text("Todavía no agregaste ninguna app. Tocá \"Agregar app\" y elegí una de las que ya usaste para dictar.")
                        .font(T.sans(13)).foregroundStyle(T.muted)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(T.panel, in: RoundedRectangle(cornerRadius: 12))
            } else {
                RowList(items: configured) { r in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            if let icon = AppIcon.image(r.id) { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                            Text(r.name).font(T.sans(13, .medium)).foregroundStyle(T.text)
                            Spacer()
                            Button { store.appPrompts[r.id] = nil } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(T.muted).help("Quitar")
                        }
                        TextEditor(text: Binding(get: { store.appPrompts[r.id] ?? "" }, set: { store.appPrompts[r.id] = $0 }))
                            .font(T.sans(13)).scrollContentBackground(.hidden).frame(height: 64)
                            .padding(8).background(T.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(14)
                }
            }
        }
        .padding(.top, 6)
    }
}

enum AppIcon {
    /// Nombre visible de la app a partir de su bundle id (o el propio id si no está instalada).
    static func name(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func image(_ bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

// MARK: Transforms

struct TransformsPage: View {
    @ObservedObject var store = Store.shared
    @AppStorage("transforms") var enabled = true
    @AppStorage("autoTransform") var auto = ""
    @State var editing: Transform?
    let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Transforms", badge: "Beta") {
                Toggle("Activado", isOn: $enabled).toggleStyle(.switch).font(T.sans(13))
            }
            Hero(title: "Transforms funciona donde escribas",
                 subtitle: "Seleccioná un texto en cualquier app y apretá ⌥ más un número: el LLM local lo reescribe y lo pega en su lugar.",
                 colors: [Color(hex: 0x1F3B3E), Color(hex: 0x2F5D62), Color(hex: 0x6B4A33)]) {
                HStack(spacing: 6) { HeroChip(text: "⌥ 1"); HeroChip(text: "Pulir", italic: true) }
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aplicar después de cada dictado").font(T.sans(14, .medium)).foregroundStyle(T.text)
                    Text("Pasa el dictado por un transform antes de pegarlo. Suma unos segundos.")
                        .font(T.sans(12)).foregroundStyle(T.muted)
                }
                Spacer()
                Picker("", selection: $auto) {
                    Text("Ninguno").tag("")
                    ForEach(store.transforms) { Text($0.name).tag($0.id.uuidString) }
                }.labelsHidden().frame(width: 180)
            }
            .padding(16).background(T.panel, in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Text("Mis transforms").font(T.serif(22)).foregroundStyle(T.text)
                Spacer()
                SoftButton("Restablecer") { store.transforms = Transform.defaults; auto = "" }
                DarkButton("Crear") { editing = Transform() }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(Array(store.transforms.enumerated()), id: \.element.id) { i, t in
                    Button { editing = t } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 4) {
                                if i < keys.count { Key(text: "⌥"); Key(text: keys[i]) }
                                Spacer()
                                if auto == t.id.uuidString { Chip(text: "Automático") }
                            }
                            Text(t.name).font(T.serif(22)).foregroundStyle(T.text)
                            Text(t.detail).font(T.sans(12)).foregroundStyle(T.muted).lineLimit(2)
                        }
                        .padding(16).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .background(T.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
                    }.buttonStyle(.plain)
                }
                Button { editing = Transform() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 18))
                        Text("Creá la tuya").font(T.sans(13, .medium))
                    }
                    .foregroundStyle(T.muted).frame(maxWidth: .infinity, minHeight: 130)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line, style: StrokeStyle(lineWidth: 1, dash: [5])))
                }.buttonStyle(.plain)
            }
            .opacity(enabled ? 1 : 0.5)
        }
        .overlay { if let t = editing { TransformEditor(transform: t) { editing = nil } } }
    }
}

struct TransformEditor: View {
    @State var transform: Transform
    let onClose: () -> Void

    var exists: Bool { Store.shared.transforms.contains { $0.id == transform.id } }

    var body: some View {
        Modal(title: exists ? "Editar transform" : "Nuevo transform", width: 520, onClose: onClose) {
            Field(label: "Nombre", text: $transform.name)
            Field(label: "Descripción corta", text: $transform.detail)
            Field(label: "Instrucción para el LLM", text: $transform.prompt, multiline: true)
            HStack {
                if exists {
                    Button("Borrar") {
                        Store.shared.transforms.removeAll { $0.id == transform.id }
                        onClose()
                    }.buttonStyle(.plain).foregroundStyle(.red).font(T.sans(13))
                }
                Spacer()
                DarkButton("Guardar", action: save)
            }
        }
    }

    func save() {
        guard !transform.name.isEmpty, !transform.prompt.isEmpty else { return onClose() }
        let store = Store.shared
        if let i = store.transforms.firstIndex(where: { $0.id == transform.id }) { store.transforms[i] = transform }
        else { store.transforms.append(transform) }
        onClose()
    }
}

// MARK: Notas

struct NotesPage: View {
    @ObservedObject var store = Store.shared
    @State var open: UUID?
    @State var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Notas", badge: "Beta") { EmptyView() }
            if let id = open, let i = store.notes.firstIndex(where: { $0.id == id }) {
                editor(i)
            } else {
                list
            }
        }
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 20) {
            Hero(title: "Para las ideas sueltas que querés retomar",
                 subtitle: "Abrí una nota y dictá con fn como en cualquier otra app. Queda guardada acá, en tu Mac.",
                 colors: [Color(hex: 0x4A3A28), Color(hex: 0x8A6A45), Color(hex: 0x3E5A4C)]) {
                Button(action: newNote) {
                    Text("Nueva nota").font(T.sans(13, .medium)).foregroundStyle(Color(hex: 0x1C1B1A))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(hex: 0xF6F3EE), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            HStack {
                Text("Recientes").font(T.serif(22)).foregroundStyle(T.text)
                Spacer()
                SearchField(text: $query)
            }
            let notes = store.notes.filter { query.isEmpty || $0.body.localizedCaseInsensitiveContains(query) }
                .sorted { $0.updated > $1.updated }
            if notes.isEmpty {
                Text("No hay notas.").font(T.sans(14)).foregroundStyle(T.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                RowList(items: notes) { n in
                    EditableRow(onEdit: { open = n.id }, onDelete: { store.notes.removeAll { $0.id == n.id } }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(n.title).font(T.sans(14, .medium)).foregroundStyle(T.text)
                            Text(n.updated.formatted(.relative(presentation: .named).locale(es)))
                                .font(T.sans(11)).foregroundStyle(T.muted)
                        }
                    }
                    .onTapGesture { open = n.id }
                }
            }
        }
    }

    func editor(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { open = nil } label: { Label("Notas", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(T.muted).font(T.sans(13))
                Spacer()
                Text(store.notes[i].updated.formatted(.dateTime.day().month().hour().minute().locale(es)))
                    .font(T.sans(11)).foregroundStyle(T.muted)
            }
            TextEditor(text: Binding(get: { store.notes[i].body }, set: {
                store.notes[i].body = $0
                store.notes[i].updated = Date()
            }))
            .font(T.sans(15)).scrollContentBackground(.hidden)
            .padding(14).frame(minHeight: 420)
            .background(T.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
        }
    }

    func newNote() {
        let n = Note()
        store.notes.insert(n, at: 0)
        open = n.id
    }
}
