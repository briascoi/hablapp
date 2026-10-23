// Contexto efímero de la ventana activa. Sólo Accesibilidad, sin capturas ni historial.
import Cocoa

enum ScreenContext {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "screenContext") as? Bool ?? true }
    static let textLimit = 2400

    static func isSecure(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.015)
        let role: String = Ctx.attr(element, kAXSubroleAttribute) ?? ""
        return role == kAXSecureTextFieldSubrole
    }

    static func read(window: AXUIElement) -> String {
        let deadline = Date().addingTimeInterval(0.18)
        var pending: [(AXUIElement, Int)] = [(window, 0)]
        var seen = Set<CFHashCode>(), fragments = [String](), count = 0, visited = 0
        let frame = rect(window)
        while let (element, depth) = pending.popLast(), visited < 120, count < textLimit, Date() < deadline {
            visited += 1
            guard seen.insert(CFHash(element)).inserted, !isSecure(element) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.015)
            let hidden: Bool = Ctx.attr(element, "AXHidden") ?? false
            if hidden { continue }
            if let bounds = rect(element), let frame, !bounds.intersects(frame) { continue }
            let role: String = Ctx.attr(element, kAXRoleAttribute) ?? ""
            // No leer valores de formularios: los nombres se obtienen de textos y etiquetas.
            let attributes = role == kAXStaticTextRole ? [kAXValueAttribute, kAXTitleAttribute] : [kAXTitleAttribute]
            for attribute in attributes {
                if let value: String = Ctx.attr(element, attribute) {
                    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, !fragments.contains(text) {
                        let piece = String(text.prefix(textLimit - count))
                        fragments.append(piece); count += piece.count + 1
                    }
                }
            }
            guard depth < 12 else { continue }
            let children: [AXUIElement] = Ctx.attr(element, kAXVisibleChildrenAttribute)
                ?? Ctx.attr(element, kAXChildrenAttribute) ?? []
            pending.append(contentsOf: children.prefix(120 - visited).reversed().map { ($0, depth + 1) })
        }
        return String(fragments.joined(separator: "\n").prefix(textLimit))
    }

    private static func rect(_ element: AXUIElement) -> CGRect? {
        guard let position: AXValue = Ctx.attr(element, kAXPositionAttribute),
              let size: AXValue = Ctx.attr(element, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    /// Lista acotada de términos. El diccionario explícito tiene prioridad sobre la pantalla.
    static func vocabulary(_ context: Context, words: [Word]) -> [String] {
        var terms = [String](), seen = Set<String>()
        func add(_ value: String) {
            let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...64).contains(term.count), terms.count < 80,
                  seen.insert(term.lowercased()).inserted else { return }
            terms.append(term)
        }
        for word in words { add(word.isReplacement ? word.to : word.from) }
        // Sólo nombres, siglas y términos con mayúsculas internas; no mandar toda la ventana al ASR.
        let source = [context.title, context.before, context.selected, context.after, context.screenText].joined(separator: "\n")
        let pattern = #"\b[\p{L}][\p{L}\p{N}._+-]*(?:[ ]+[A-ZÁÉÍÓÚÑ][\p{L}\p{N}._+-]*){0,2}\b"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source) else { continue }
                let term = String(source[range])
                if term.unicodeScalars.contains(where: CharacterSet.uppercaseLetters.contains) { add(term) }
            }
        }
        return terms
    }

    /// Corrige únicamente grafías cercanas a términos visibles, sin generar texto desde la ventana.
    /// Una coincidencia ambigua se deja intacta. No reemplaza palabras comunes por frases de la pantalla.
    static func correctNames(_ text: String, vocabulary: [String]) -> String {
        func key(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
        }
        func distance(_ left: String, _ right: String) -> Int {
            let a = Array(left), b = Array(right)
            var row = Array(0...b.count)
            for (i, x) in a.enumerated() {
                var next = [i + 1] + Array(repeating: 0, count: b.count)
                for (j, y) in b.enumerated() { next[j + 1] = min(next[j] + 1, row[j + 1] + 1, row[j] + (x == y ? 0 : 1)) }
                row = next
            }
            return row[b.count]
        }
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#) else { return text }
        let tokens = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let candidates = vocabulary.map { ($0, key($0)) }.filter { (5...40).contains($0.1.count) }
        let ns = text as NSString
        let connectors: Set<String> = ["y", "o", "de", "del", "el", "la", "los", "las", "un", "una", "en", "con", "por", "para", "a", "al"]
        var replacements = [(NSRange, String)](), index = 0
        while index < tokens.count {
            var best: (NSRange, String, Double, Int)?
            var ambiguous = false
            for length in 1...min(3, tokens.count - index) {
                let range = NSRange(location: tokens[index].range.location,
                                    length: NSMaxRange(tokens[index + length - 1].range) - tokens[index].range.location)
                let original = ns.substring(with: range)
                if length > 1 {
                    let first = key(ns.substring(with: tokens[index].range))
                    let last = key(ns.substring(with: tokens[index + length - 1].range))
                    if connectors.contains(first) || connectors.contains(last) { continue }
                }
                // No unir palabras separadas por puntuación u oraciones.
                if original.contains(where: { !$0.isLetter && !$0.isNumber && $0 != " " }) { continue }
                let normalized = key(original)
                for (canonical, candidate) in candidates {
                    guard abs(normalized.count - candidate.count) <= 3 else { continue }
                    if !canonical.contains(" "), candidate == normalized + "s" || normalized == candidate + "s"
                        || candidate == normalized + "es" || normalized == candidate + "es" { continue }
                    let edits = distance(normalized, candidate)
                    let score = Double(edits) / Double(max(normalized.count, candidate.count))
                    guard edits <= 3, score <= (candidate.count >= 9 ? 0.31 : 0.20) else { continue }
                    // Una etiqueta común con mayúscula inicial no cambia la capitalización de una oración.
                    if edits == 0, !canonical.contains(" "), canonical != canonical.uppercased(),
                       !canonical.dropFirst().contains(where: \.isUppercase), original != canonical { continue }
                    if let previous = best, abs(score - previous.2) < 0.025 {
                        if canonical.lowercased() != previous.1.lowercased() { ambiguous = true }
                    } else if best == nil || score < best!.2 {
                        best = (range, canonical, score, length); ambiguous = false
                    }
                }
            }
            if let best, !ambiguous {
                if ns.substring(with: best.0) != best.1 { replacements.append((best.0, best.1)) }
                index += best.3
            } else { index += 1 }
        }
        let output = NSMutableString(string: text)
        for (range, value) in replacements.reversed() { output.replaceCharacters(in: range, with: value) }
        return output as String
    }
}
