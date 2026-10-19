// Esquema hablapp:// para Atajos, Raycast y scripts. El parseo es puro (se prueba en --selftest);
// la ejecución vive en Engine.run(_:).

import Foundation

enum DeepLink: Equatable {
    case start, stop, toggle, cancel, pasteLast
    case transform(String)

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "hablapp",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let route = ((c.host?.isEmpty == false ? c.host : nil) ?? c.path.split(separator: "/").first.map(String.init) ?? "").lowercased()
        switch route {
        case "start": return .start
        case "stop": return .stop
        case "toggle": return .toggle
        case "cancel": return .cancel
        case "paste-last": return .pasteLast
        case "transform":
            let name = (c.queryItems?.first { $0.name == "name" }?.value ?? "").trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : .transform(name)
        default: return nil
        }
    }

    /// Las URLs documentadas (Atajos > Ayuda y README).
    static let docs: [(String, String)] = [
        ("hablapp://start", "Empieza a dictar en manos libres"),
        ("hablapp://stop", "Termina y pega"),
        ("hablapp://toggle", "Empieza o termina, según el estado"),
        ("hablapp://cancel", "Descarta el dictado en curso"),
        ("hablapp://paste-last", "Pega la última transcripción"),
        ("hablapp://transform?name=Pulir", "Aplica el transform a la selección"),
    ]
}
