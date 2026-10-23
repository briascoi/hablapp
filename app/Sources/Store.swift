// Datos de la app: historial, diccionario, snippets, transforms y notas en JSON
// (~/Library/Application Support/hablapp). Los ajustes van en UserDefaults vía @AppStorage.

import Foundation
import SwiftUI

enum Category: String, Codable, CaseIterable, Identifiable {
    case personal, work, email, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .personal: "Mensajes personales"
        case .work: "Mensajes de trabajo"
        case .email: "Email"
        case .other: "Otros"
        }
    }
    var tab: String {
        switch self {
        case .personal: "Personales"
        case .work: "Trabajo"
        case .email: "Email"
        case .other: "Otros"
        }
    }
    var icon: String {
        switch self {
        case .personal: "message"
        case .work: "bubble.left.and.text.bubble.right"
        case .email: "envelope"
        case .other: "doc.text"
        }
    }
    var defaultTone: Tone { self == .personal ? .casual : .formal }
}

enum Tone: String, Codable, CaseIterable, Identifiable {
    case formal, casual, veryCasual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .formal: "Formal"
        case .casual: "Casual"
        case .veryCasual: "Muy casual"
        }
    }
    var subtitle: String {
        switch self {
        case .formal: "Mayúsculas y puntuación"
        case .casual: "Mayúsculas y menos puntuación"
        case .veryCasual: "Sin mayúsculas y menos puntuación"
        }
    }
    var sample: String {
        switch self {
        case .formal: "Hola, ¿estás libre para almorzar mañana? Hagamos a las 12 si te queda bien."
        case .casual: "Hola, ¿estás libre para almorzar mañana? Hagamos a las 12 si te queda bien"
        case .veryCasual: "hola estás libre para almorzar mañana? hagamos a las 12 si te queda bien"
        }
    }
}

struct Entry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var app = ""
    var category: Category = .other
    var raw = ""
    var text = ""
    var words = 0
    var seconds = 0.0
    var kind = "dictado"
    var bundle: String? = nil  // bundle id de la app; opcional para leer historiales viejos
}

struct Word: Codable, Identifiable, Hashable {
    var id = UUID()
    var from = ""
    var to = ""  // vacío: palabra a escribir tal cual; con valor: reemplazo
    var isReplacement: Bool { !to.isEmpty }
}

struct Snippet: Codable, Identifiable {
    var id = UUID()
    var trigger = ""
    var text = ""
}

struct Transform: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var detail = ""
    var prompt = ""
    var producesPrompt: Bool? = nil  // opcional para conservar los JSON anteriores
    var createsPrompt: Bool { producesPrompt ?? (name == "Prompt engineer") }

    static let promptEngineer = """
    Convertí el dictado en instrucciones claras para otra IA. Pedí directamente la tarea original:
    crear una presentación, investigar, comparar, programar, redactar un mensaje, etc.
    Ordená objetivo, datos y restricciones sin inventar información ni ejecutar la tarea.
    Conservá el destinatario sólo si el dictado pide escribirle a alguien.
    Conservá condiciones, negaciones, cifras, plazos y el registro del dictado.
    Entregá únicamente el prompt listo para copiar a otra IA.
    """

    static let defaults = [
        Transform(name: "Pulir", detail: "Más claro y conciso",
                  prompt: "Reescribí el texto para que sea más claro y conciso, sin cambiar el significado, el idioma ni el registro."),
        Transform(name: "Prompt engineer", detail: "Mejora el prompt con tu propia API",
                  prompt: promptEngineer, producesPrompt: true),
        Transform(name: "Al inglés", detail: "Traduce manteniendo el tono",
                  prompt: "Traducí el texto al inglés natural, manteniendo el tono y el formato."),
    ]
}

struct Note: Codable, Identifiable {
    var id = UUID()
    var body = ""
    var updated = Date()
    var title: String {
        let first = body.split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty ? "Sin título" : String(first.prefix(60))
    }
}

final class Store: ObservableObject {
    static let shared = Store()

    @Published var history: [Entry] = [] { didSet { save("history", history) } }
    @Published var words: [Word] = [] { didSet { save("dictionary", words) } }
    @Published var snippets: [Snippet] = [] { didSet { save("snippets", snippets) } }
    @Published var transforms: [Transform] = [] {
        didSet {
            save("transforms", transforms)
            let ids = Set(transforms.map { $0.id.uuidString })
            // Una regla cuyo transform se borró queda en «Ninguno».
            appTransforms = appTransforms.mapValues { ids.contains($0) ? $0 : "" }
            if let id = preferences.string(forKey: "autoTransform"), !ids.contains(id) {
                preferences.removeObject(forKey: "autoTransform")
            }
        }
    }
    @Published var notes: [Note] = [] { didSet { save("notes", notes) } }
    @Published var suggestions: [Word] = [] { didSet { save("suggestions", suggestions) } }  // correcciones aprendidas, pendientes
    @Published var appPrompts: [String: String] = [:] { didSet { save("app-prompts", appPrompts) } }  // bundle id -> instrucciones
    @Published var appTransforms: [String: String] = [:] { didSet { save("app-transforms", appTransforms) } } // sin clave: general; vacío: ninguno
    @AppStorage("fixes") var fixes = 0

    let dir: URL
    private let preferences: UserDefaults

    init(directory: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        // HABLAPP_DATA permite probar (snapshots) con datos de prueba sin tocar los reales.
        dir = directory ?? ProcessInfo.processInfo.environment["HABLAPP_DATA"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("hablapp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        history = load("history") ?? []
        words = load("dictionary") ?? []
        snippets = load("snippets") ?? []
        // Cargar las reglas antes de los transforms: su didSet limpia referencias borradas y las guarda.
        appTransforms = load("app-transforms") ?? [:]
        let saved: [Transform] = load("transforms") ?? Transform.defaults
        transforms = saved.map(Self.migrateTransform)
        notes = load("notes") ?? []
        suggestions = load("suggestions") ?? []
        appPrompts = load("app-prompts") ?? [:]
        prune()
    }

    private func load<V: Decodable>(_ name: String) -> V? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name + ".json")) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(V.self, from: data)
    }

    private func save<V: Encodable>(_ name: String, _ value: V) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        try? e.encode(value).write(to: dir.appendingPathComponent(name + ".json"), options: .atomic)
    }

    // Retención del historial (Ajustes > Datos y privacidad).
    func prune() {
        let days = preferences.integer(forKey: "historyDays")
        guard days > 0 else { return }
        let limit = Date().addingTimeInterval(-Double(days) * 86400)
        if history.contains(where: { $0.date < limit }) { history.removeAll { $0.date < limit } }
    }

    func add(_ entry: Entry) {
        if preferences.integer(forKey: "historyDays") < 0 {
            // "No guardar": igual sumamos a las estadísticas, sin el texto.
            var e = entry
            e.raw = ""; e.text = ""
            history.insert(e, at: 0)
        } else {
            history.insert(entry, at: 0)
        }
    }

    // MARK: estadísticas

    var dictations: [Entry] { history.filter { $0.kind == "dictado" } }
    var totalWords: Int { history.reduce(0) { $0 + $1.words } }

    var wpm: Int {
        let timed = dictations.filter { $0.seconds > 1 }
        let secs = timed.reduce(0) { $0 + $1.seconds }
        return secs > 0 ? Int(Double(timed.reduce(0) { $0 + $1.words }) / secs * 60) : 0
    }

    var wordsByDay: [Date: Int] {
        var out: [Date: Int] = [:]
        let cal = Calendar.current
        for e in history { out[cal.startOfDay(for: e.date), default: 0] += e.words }
        return out
    }

    var wordsToday: Int { wordsByDay[Calendar.current.startOfDay(for: Date())] ?? 0 }

    var streak: Int {
        let days = wordsByDay
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if days[day] == nil { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while days[day] != nil { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }

    var longestStreak: Int {
        let days = wordsByDay.keys.sorted()
        let cal = Calendar.current
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            run = (prev.flatMap { cal.dateComponents([.day], from: $0, to: d).day } == 1) ? run + 1 : 1
            best = max(best, run)
            prev = d
        }
        return best
    }

    func usage() -> [(Category, Int)] {
        let total = max(dictations.count, 1)
        return Category.allCases.map { c in (c, dictations.filter { $0.category == c }.count * 100 / total) }
    }
}
