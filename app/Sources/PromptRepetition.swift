// Control local conservador: detecta frases largas repetidas, sin eliminar contenido automáticamente.
import Foundation

enum PromptRepetition {
    static func phrases(in text: String, original: String) -> [String] {
        // Una petición explícita de repetición se conserva. No confundirla con «no repitas».
        let request = Formatter.norm(original)
        if request.range(of: #"(?<!no )\b(?:repeti|repite|repetilo|repitelo)\b"#, options: .regularExpression) != nil { return [] }
        let sentences = text.components(separatedBy: .newlines).flatMap {
            $0.components(separatedBy: CharacterSet(charactersIn: ".!?;"))
        }.map { Formatter.norm($0).split(separator: " ").map(String.init) }.filter { !$0.isEmpty }
        var seen: [String: Int] = [:]
        var repeated = [String]()
        for (index, words) in sentences.enumerated() {
            var phrases = [String]()
            if words.count >= 4 { phrases.append(words.joined(separator: " ")) }
            if words.count >= 7 {
                phrases += (0...(words.count - 7)).map { words[$0..<($0 + 7)].joined(separator: " ") }
            }
            for phrase in Set(phrases) {
                if let previous = seen[phrase], previous != index, !repeated.contains(phrase) {
                    repeated.append(phrase)
                } else if seen[phrase] == nil { seen[phrase] = index }
            }
        }
        // Priorizar las coincidencias más largas, con orden estable para diagnósticos y pruebas.
        return Array(repeated.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }.prefix(4))
    }
}
