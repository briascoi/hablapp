// Diccionario que aprende: 8 s después de pegar, compara lo pegado con lo que quedó en el campo
// y propone como "sugeridas" las palabras que corregiste a mano. Nunca agrega solo.

import Cocoa

enum Learner {
    static let maxPending = 20

    /// Se llama justo después de pegar un dictado. `app` es el bundle id de la app donde se pegó.
    static func watch(pasted: String, app bundle: String) {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundle.isEmpty, !text.isEmpty else { return }
        Task.detached {
            try? await Task.sleep(for: .seconds(8))
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle else { return }
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.25)
            guard let el: AXUIElement = Ctx.attr(system, kAXFocusedUIElementAttribute),
                  let field: String = Ctx.attr(el, kAXValueAttribute) else { return }
            let found = corrections(pasted: text, field: field)
            guard !found.isEmpty else { return }
            await MainActor.run { for (from, to) in found { suggest(from, to) } }
        }
    }

    // MARK: sugeridas

    private static let rejectedKey = "rejectedSuggestions"
    private static func key(_ from: String, _ to: String) -> String { from.lowercased() + "|" + to }

    static func suggest(_ from: String, _ to: String) {
        let s = Store.shared
        let rejected = UserDefaults.standard.stringArray(forKey: rejectedKey) ?? []
        guard s.suggestions.count < maxPending,
              !rejected.contains(key(from, to)),
              !s.words.contains(where: { $0.from.lowercased() == from.lowercased() }),
              !s.suggestions.contains(where: { $0.from.lowercased() == from.lowercased() }) else { return }
        s.suggestions.append(Word(from: from, to: to))
    }

    static func accept(_ w: Word) {
        Store.shared.suggestions.removeAll { $0.id == w.id }
        Store.shared.words.append(Word(from: w.from, to: w.to))
    }

    /// Descartar la recuerda (hasta 200) para no volver a sugerirla.
    static func discard(_ w: Word) {
        Store.shared.suggestions.removeAll { $0.id == w.id }
        let rejected = UserDefaults.standard.stringArray(forKey: rejectedKey) ?? []
        UserDefaults.standard.set(Array((rejected + [key(w.from, w.to)]).suffix(200)), forKey: rejectedKey)
    }

    // MARK: detección (pura, probada en --selftest)

    /// Criterio: se alinea el texto pegado contra el tramo más parecido del campo (distancia de edición por
    /// palabras, con extremos libres porque el campo trae texto antes y después). Cuenta como corrección una
    /// sustitución 1 a 1 `viejo -> nuevo` si:
    ///  - el pegado tiene 2+ palabras y al menos la mitad (y no menos que las sustituciones) coincide con el campo,
    ///    así no se aprende de reescrituras ni de coincidencias casuales;
    ///  - ninguna de las dos tiene dígitos y ambas tienen 2+ letras;
    ///  - cambia sólo la mayúscula, o la distancia de edición entre ambas es <= 3 (sonaban parecido),
    ///    o la nueva empieza con mayúscula y la vieja no (nombre propio).
    /// Campos de más de 3000 palabras se ignoran.
    static func corrections(pasted: String, field: String) -> [(String, String)] {
        let a = tokens(pasted), b = tokens(field)
        let n = a.count, m = b.count
        guard n >= 2, m >= 1, m <= 3000 else { return [] }
        func sub(_ x: String, _ y: String) -> Int { x == y ? 0 : x.lowercased() == y.lowercased() ? 1 : 2 }  // indel cuesta 3: se prefiere alinear palabra con palabra
        var d = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { d[i][0] = 3 * i }
        for i in 1...n {
            for j in 1...m {
                d[i][j] = min(d[i - 1][j - 1] + sub(a[i - 1], b[j - 1]), d[i - 1][j] + 3, d[i][j - 1] + 3)
            }
        }
        var j = (0...m).reversed().min { d[n][$0] < d[n][$1] }!  // en empate, el tramo más tarde
        var i = n
        var pairs: [(String, String)] = []
        var anchors = 0
        while i > 0 {
            if j > 0, d[i][j] == d[i - 1][j - 1] + sub(a[i - 1], b[j - 1]) {
                if a[i - 1].lowercased() == b[j - 1].lowercased() { anchors += 1 }
                if a[i - 1] != b[j - 1] { pairs.append((a[i - 1], b[j - 1])) }
                i -= 1; j -= 1
            } else if d[i][j] == d[i - 1][j] + 3 { i -= 1 } else { j -= 1 }
        }
        let subs = pairs.filter { $0.0.lowercased() != $0.1.lowercased() }.count
        guard anchors * 2 >= n, anchors >= subs else { return [] }
        var seen = Set<String>()
        return pairs.reversed().filter { plausible($0.0, $0.1) && seen.insert($0.0.lowercased()).inserted }
    }

    private static func plausible(_ old: String, _ new: String) -> Bool {
        let letters = { (s: String) in s.filter(\.isLetter).count }
        guard letters(old) >= 2, letters(new) >= 2, !old.contains(where: \.isNumber), !new.contains(where: \.isNumber) else { return false }
        if old.lowercased() == new.lowercased() { return true }
        return distance(old.lowercased(), new.lowercased()) <= 3 || (new.first?.isUppercase == true && old.first?.isUppercase == false)
    }

    private static func tokens(_ s: String) -> [String] {
        let edge = CharacterSet.punctuationCharacters.union(.symbols)
        return s.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: edge) }.filter { !$0.isEmpty }
    }

    private static func distance(_ x: String, _ y: String) -> Int {
        let a = Array(x), b = Array(y)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return row[b.count]
    }
}
