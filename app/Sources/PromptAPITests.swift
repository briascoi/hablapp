// Pruebas sin red. No usan ni modifican la clave del usuario.
import Foundation

private final class PromptMockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

enum PromptAPITests {
    static func response(prompt: String, coverage: [(Int, String)] = [],
                         omitted: [String] = [], editorialIssues: [String] = [], status: String = "completed") -> Data {
        let draft = try! JSONSerialization.data(withJSONObject: ["prompt": prompt,
            "coverage": coverage.map { ["source_id": $0.0, "prompt_excerpt": $0.1] as [String: Any] },
            "omitted_details": omitted, "editorial_issues": editorialIssues])
        return try! JSONSerialization.data(withJSONObject: ["status": status,
            "output": [["type": "message", "content": [["type": "output_text", "text": String(decoding: draft, as: UTF8.self)]]]],
            "usage": ["input_tokens": 1000, "output_tokens": 500]])
    }

    static func run() async -> Int32 {
        var failures = 0, checks = 0
        func check(_ name: String, _ condition: Bool) {
            checks += 1
            if !condition { failures += 1 }
            print("\(condition ? "ok" : "FALLA") API: \(name)")
        }
        let fakeKey = "sk-prueba-local-sin-valor-real"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PromptMockProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); PromptMockProtocol.handler = nil }
        do {
            let request = try PromptAPI.request(text: "Compará A y B para 3 personas si puede", preferences: "Ser breve", key: fakeKey, model: .standard)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            check("destino HTTPS fijo", request.url == PromptAPI.endpoint)
            check("credencial sólo en cabecera", request.value(forHTTPHeaderField: "Authorization") == "Bearer " + fakeKey && !String(decoding: request.httpBody!, as: UTF8.self).contains(fakeKey))
            check("almacenamiento de respuesta desactivado", body["store"] as? Bool == false)
            check("límite de salida y razonamiento bajo", body["max_output_tokens"] as? Int == 2400 && (body["reasoning"] as? [String: String])?["effort"] == "low")
            let input = try JSONSerialization.jsonObject(with: Data((body["input"] as! String).utf8)) as! [String: Any]
            check("sin audio, historial ni ventana", Set(input.keys) == ["dictation", "transform_preferences", "fidelity_points"])
        } catch { check("construcción de solicitud", false) }

        PromptMockProtocol.calls = 0
        let finalPrompt = "Compará A y B para 3 personas si puede."
        let redundant = finalPrompt + " " + finalPrompt
        PromptMockProtocol.handler = { _ in (200, response(prompt: PromptMockProtocol.calls == 1 ? redundant : finalPrompt)) }
        do {
            let result = try await PromptAPI.improve("Compará A y B para 3 personas si puede", preferences: "", key: fakeKey, model: .standard, session: session)
            check("respuesta HTTP y JSON interpretada", result.text == "Compará A y B para 3 personas si puede.")
            check("consumo desde respuesta real de transporte simulado", result.inputTokens == 2000 && result.outputTokens == 1000 && result.requests == 2 && result.usageComplete && abs(result.estimatedCost - 0.020) < 0.0000001)
        } catch { check("recorrido de transporte", false) }
        check("dos etapas sin llamadas extra", PromptMockProtocol.calls == 2)
        do {
            var payload = try JSONSerialization.jsonObject(with: response(prompt: finalPrompt)) as! [String: Any]
            payload.removeValue(forKey: "usage")
            let result = try PromptAPI.parse(JSONSerialization.data(withJSONObject: payload), original: finalPrompt, model: .standard)
            check("ausencia de consumo no se presenta como medición completa", !result.usageComplete)
        } catch { check("ausencia de consumo", false) }
        do {
            let request = try PromptAPI.request(text: finalPrompt, preferences: "", key: fakeKey, model: .standard, draft: redundant)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let input = try JSONSerialization.jsonObject(with: Data((body["input"] as! String).utf8)) as! [String: Any]
            check("editor recibe original y borrador", input["dictation"] as? String == finalPrompt && input["draft"] as? String == redundant)
            check("editor recibe diagnóstico de repeticiones", !(input["known_repetitions"] as? [String] ?? []).isEmpty)
            check("revisión con instrucciones independientes", body["instructions"] as? String == PromptAPI.editorInstructions)
        } catch { check("solicitud editorial", false) }

        PromptMockProtocol.calls = 0
        PromptMockProtocol.handler = { _ in (200, response(prompt: redundant)) }
        do {
            _ = try await PromptAPI.improve(finalPrompt, preferences: "", key: fakeKey, model: .standard, session: session)
            check("no entrega un resultado que sigue repetido", false)
        } catch let error as PromptPreservationError {
            check("no entrega un resultado que sigue repetido", error.localizedDescription == PromptAPIError.editorial.localizedDescription)
            check("rechazo suma consumo de ambas etapas", error.result.requests == 2 && error.result.inputTokens == 2000 && error.result.outputTokens == 1000)
        } catch { check("rechazo de repetición final", false) }
        check("repetición rechazada sin reintentar", PromptMockProtocol.calls == 2)

        PromptMockProtocol.calls = 0
        PromptMockProtocol.handler = { _ in
            PromptMockProtocol.calls == 1 ? (200, response(prompt: finalPrompt)) : (500, Data())
        }
        do {
            _ = try await PromptAPI.improve(finalPrompt, preferences: "", key: fakeKey, model: .standard, session: session)
            check("no entrega borrador si falla el editor", false)
        } catch let error as PromptPreservationError {
            check("no entrega borrador si falla el editor", error.localizedDescription == PromptAPIError.server.localizedDescription)
            check("error del editor conserva consumo parcial conocido", error.result.requests == 2 && !error.result.usageComplete && error.result.inputTokens == 1000)
        } catch { check("fallo del editor", false) }
        check("fallo del editor no se reintenta", PromptMockProtocol.calls == 2)

        PromptMockProtocol.calls = 0
        PromptMockProtocol.handler = { _ in (200, response(prompt: PromptMockProtocol.calls == 1 ? "Compará A y B." : finalPrompt)) }
        do {
            let result = try await PromptAPI.improve(finalPrompt, preferences: "", key: fakeKey, model: .standard, session: session)
            check("editor puede recuperar datos omitidos del borrador", result.text == finalPrompt && result.draftText == "Compará A y B.")
        } catch { check("editor recupera datos", false) }


        let source = "Prepará el informe de 3 indicadores. Lo más importante es que los datos se puedan verificar. Si es posible, creo que podríamos incorporar el control en el equipo."
        let priority = "Lo principal es que los datos sean verificables."
        let proposal = "Si es posible, evaluá incorporar este control en el equipo."
        let complete = "Prepará un informe de 3 indicadores. " + priority + "\n\n" + proposal
        do {
            let result = try PromptAPI.parse(response(prompt: complete, coverage: [(0, priority), (1, proposal)]), original: source, model: .standard)
            check("devuelve el prompt completo sin insertar bloques", result.text == complete)
            check("propuesta secundaria integrada", result.text.contains(proposal) && !result.text.contains("Propuestas para evaluar:"))
            check("una sola mención de la prioridad", result.text.components(separatedBy: priority).count == 2)
        } catch { check("integración de prioridad y propuestas", false) }
        for (name, coverage) in [
            ("rechaza ausencia de cobertura", [(Int, String)]()),
            ("rechaza cita ausente del prompt", [(0, "Texto inventado"), (1, proposal)]),
            ("rechaza propuesta sin comprobación", [(0, priority)]),
            ("rechaza referencia ajena al dictado", [(0, priority), (1, proposal), (99, priority)]),
            ("rechaza referencias duplicadas", [(0, priority), (0, priority), (1, proposal)])
        ] {
            do { _ = try PromptAPI.parse(response(prompt: complete, coverage: coverage), original: source, model: .standard); check(name, false) }
            catch { check(name, true) }
        }

        for (code, expected) in [(401, PromptAPIError.authentication), (429, .quota), (500, .server)] {
            PromptMockProtocol.calls = 0
            PromptMockProtocol.handler = { _ in (code, Data("respuesta privada que no debe mostrarse".utf8)) }
            do {
                _ = try await PromptAPI.improve("Compará A y B", preferences: "", key: fakeKey, model: .standard, session: session)
                check("rechazo HTTP \(code)", false)
            } catch {
                check("rechazo HTTP \(code) sin detalles privados", error.localizedDescription == expected.localizedDescription)
            }
            check("HTTP \(code) no se reintenta", PromptMockProtocol.calls == 1)
        }
        PromptMockProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await PromptAPI.improve("Compará A y B", preferences: "", key: fakeKey, model: .standard, session: session)
            check("timeout", false)
        } catch { check("timeout conserva error seguro", error.localizedDescription == PromptAPIError.network.localizedDescription) }

        for (name, data) in [
            ("condición omitida", response(prompt: "Redactá un mensaje para el viernes")),
            ("cifra omitida", response(prompt: "Redactá un mensaje si puede")),
            ("omisión informada por el modelo", response(prompt: "Redactá 3 mensajes si puede", omitted: ["un plazo"])),
            ("problema editorial informado", response(prompt: "Redactá 3 mensajes si puede", editorialIssues: ["queda repetición"])),
            ("respuesta incompleta", response(prompt: "Redactá 3 mensajes si puede", status: "incomplete")),
            ("salida vacía", response(prompt: "")),
            ("JSON inválido", Data("no es JSON".utf8))
        ] {
            do { _ = try PromptAPI.parse(data, original: "Redactá 3 mensajes si puede", model: .standard); check(name, false) }
            catch { check(name, true) }
        }
        do { _ = try PromptAPI.request(text: String(repeating: "x", count: 12_001), preferences: "", key: fakeKey, model: .standard); check("límite de entrada", false) }
        catch { check("límite de entrada antes de enviar", true) }

        let keys = APIKeyStore(service: "com.isma.hablapp.test." + UUID().uuidString)
        defer { try? keys.delete() }
        do {
            check("cuenta de prueba aislada vacía", try keys.read() == nil)
            try keys.save(fakeKey)
            check("Llavero guarda y recupera", try keys.read() == fakeKey)
            try keys.save(fakeKey + "-actualizada")
            check("Llavero actualiza sin duplicados", try keys.read() == fakeKey + "-actualizada")
            try keys.delete()
            check("Llavero elimina la credencial", try keys.read() == nil)
        } catch { check("Llavero de prueba", false) }
        check("control de negaciones", !PromptAPI.preservesAnchors("No agregues precios. Entregá 3 opciones.", "Entregá 3 opciones con precios."))
        check("control de restricciones sin", !PromptAPI.preservesAnchors("Programá sin usar librerías externas.", "Programá usando librerías externas."))
        check("restricciones preservadas", PromptAPI.preservesAnchors("Programá sin usar librerías externas.", "Implementá la solución sin usar librerías externas."))
        check("paráfrasis fiel de intención negativa", PromptAPI.preservesAnchors("No quiero volver a perder tiempo haciendo otro video que no me convenza.", "La prioridad es no volver a perder tiempo haciendo otro video que no me convenza."))
        check("no confunde personas verbales", !PromptAPI.preservesAnchors("Mandalo si puede.", "Mandalo si puedes."))
        check("no acepta una cifra contenida en otra", !PromptAPI.preservesAnchors("Equipo de 12 personas.", "Equipo de 120 personas."))
        check("conserva signo de las cifras", !PromptAPI.preservesAnchors("Una variación de -5%.", "Una variación de 5%."))
        let negativeSource = "No quiero volver a perder tiempo haciendo otro video que no me convenza."
        let constraint = "no volver a perder tiempo haciendo otro video que no me convenza"
        let integrated = "Presentá y aprobá la idea antes de producir el video, para " + constraint + "."
        do {
            let result = try PromptAPI.parse(response(prompt: integrated, coverage: [(0, constraint)]), original: negativeSource, model: .standard)
            check("restricción integrada sin anexo ni duplicación", result.text == integrated && !result.text.contains("Restricciones del pedido"))
        } catch { check("restricción integrada sin anexo ni duplicación", false) }
        do {
            _ = try PromptAPI.parse(response(prompt: "Presentá la idea antes del video."), original: negativeSource, model: .standard)
            check("no repara omisiones pegando texto crudo", false)
        } catch let error as PromptPreservationError {
            check("no repara omisiones pegando texto crudo", error.result.text == "Presentá la idea antes del video." && !error.missingDetails.isEmpty)
        } catch { check("no repara omisiones pegando texto crudo", false) }
        do {
            _ = try PromptAPI.parse(response(prompt: "Hacé la propuesta para evitar " + constraint + ".", coverage: [(0, constraint)]), original: negativeSource, model: .standard)
            check("rechaza doble negación nueva aunque contenga el original", false)
        } catch { check("rechaza doble negación nueva aunque contenga el original", true) }
        let duplicateDescription = "Explicá la narrativa, el estilo y los lineamientos visuales. Mostrá la narrativa, el estilo y los lineamientos visuales."
        check("detecta descripción repetida con otro verbo", !PromptRepetition.phrases(in: duplicateDescription, original: "Presentá la propuesta.").isEmpty)
        check("permite referencia breve al flujo ya explicado", PromptRepetition.phrases(in: "Explicá la narrativa, el estilo y los lineamientos visuales. Evaluá incorporar este flujo en el equipo.", original: "Presentá la propuesta.").isEmpty)
        check("no confunde un nombre compartido con repetición", PromptRepetition.phrases(in: "Explicá cómo funciona Acme Studio para los clientes. Compará Acme Studio con otras opciones disponibles.", original: "Compará el producto.").isEmpty)
        check("conserva detalles numéricos distintos", PromptRepetition.phrases(in: "Proponé un equipo de 12 personas. Planificá 12 días de implementación.", original: "Planificá el equipo.").isEmpty)
        check("respeta repetición pedida explícitamente", PromptRepetition.phrases(in: redundant, original: "Repetí literalmente la frase dos veces.").isEmpty)
        check("prohibición de repetir no desactiva el control", !PromptRepetition.phrases(in: redundant, original: "No repitas frases.").isEmpty)
        print("API: \(checks) comprobaciones, \(failures) fallas. Sin llamadas externas.")
        return failures == 0 ? 0 : 1
    }
}
