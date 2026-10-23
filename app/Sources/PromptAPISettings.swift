import SwiftUI
import AppKit

struct PromptAPISettings: View {
    @AppStorage("promptAPI.enabled") var enabled = false
    @AppStorage("promptAPI.model") var selectedModel = PromptModel.standard.rawValue
    @ObservedObject var state = PromptAPIState.shared
    @State private var key = ""
    @State private var hasKey = false
    @State private var status = ""
    @State private var busy = false
    private let keys = APIKeyStore()
    private var model: PromptModel { PromptModel(rawValue: selectedModel) ?? .standard }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Opcional: convierte tus ideas dictadas en prompts más claros y estructurados. El audio se transcribe en tu Mac. Al activarlo, el texto y las instrucciones del transform se envían a OpenAI con tu propia cuenta.")
                .font(T.sans(13)).foregroundStyle(T.text).fixedSize(horizontal: false, vertical: true)
            Group_ {
                Toggler("Mejorar prompts con mi API", detail: hasKey ? "Clave propia guardada. Puedes desactivarla cuando quieras." : "Conecta tu clave para activar la mejora.", isOn: $enabled)
                    .disabled(!hasKey || busy)
                Row("Modelo", "La transcripción y el resto del formato siguen siendo locales.") {
                    Text(model.title).font(T.sans(13, .medium))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(hasKey ? "Cambiar mi clave de OpenAI" : "Mi clave de OpenAI").font(T.sans(13, .semibold))
                SecureField("Pega aquí tu clave de API", text: $key)
                    .textFieldStyle(.roundedBorder).privacySensitive()
                Text("Se guarda en el Llavero de macOS de tu usuario, sin sincronización de la clave. Hablapp no incluye una clave compartida ni gestiona tu saldo. La API se factura por separado de ChatGPT.")
                    .font(T.sans(12)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    DarkButton("Guardar y activar") { save() }.disabled(key.isEmpty || busy)
                    if hasKey {
                        SoftButton(busy ? "Probando…" : "Probar conexión") { test() }.disabled(busy)
                        SoftButton("Desconectar") { disconnect() }.disabled(busy)
                    }
                }
                Link("Crear una clave en mi cuenta de OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(T.sans(12))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Consumo a cargo de tu cuenta").font(T.sans(13, .semibold))
                Text("\(model.rawValue): US$ \(model.inputRate.formatted(.number.locale(Locale(identifier: "en_US")))) por millón de tokens de entrada y US$ \(model.outputRate.formatted(.number.locale(Locale(identifier: "en_US")))) de salida.")
                Text("Tarifas de referencia verificadas el 22/10/2026.")
                Text("Ejemplo de consumo total: 1.000 tokens de entrada y 500 de salida ≈ US$ \(String(format: "%.5f", locale: Locale(identifier: "en_US"), model.cost(input: 1000, output: 500))). Cada mejora realiza dos solicitudes: reescritura y revisión editorial. El consumo real suma ambas etapas. No se reintentan automáticamente.")
                Link("Consultar tarifas vigentes", destination: URL(string: "https://developers.openai.com/api/docs/models/\(model.rawValue)")!)
                Link("Ver el consumo de mi cuenta", destination: URL(string: "https://platform.openai.com/usage")!)
            }.font(T.sans(12)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if !status.isEmpty { Text(status).font(T.sans(12)).foregroundStyle(T.text).textSelection(.enabled) }
            if !state.lastUsage.isEmpty { Text("Última mejora: " + state.lastUsage).font(T.sans(12)).foregroundStyle(T.muted) }
            if !state.lastError.isEmpty { Text("Último error: " + state.lastError).font(T.sans(12)).foregroundStyle(T.text) }
            Text("Si falla alguna etapa o la revisión detecta pérdidas de datos o repeticiones largas, se conserva el dictado y se muestra un aviso. Estos controles no sustituyen tu revisión del resultado. No se envían audio, capturas, historial ni el texto completo de la ventana.")
                .font(T.sans(12)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { refresh() }
    }
    private func refresh() {
        do { hasKey = try keys.read() != nil }
        catch { status = error.localizedDescription; hasKey = false }
    }
    private func save() {
        do { try keys.save(key); key = ""; hasKey = true; enabled = true; status = "Clave guardada. La mejora de prompts está activada." }
        catch { status = error.localizedDescription }
    }
    private func disconnect() {
        do { try keys.delete(); enabled = false; hasKey = false; key = ""; status = "Cuenta desconectada. El dictado local sigue disponible." }
        catch { status = error.localizedDescription }
    }
    private func test() {
        busy = true
        status = "Probando con un pedido de ejemplo, sin usar tus dictados. Esta prueba consume tokens."
        let model = model
        Task {
            defer { busy = false }
            do {
                guard let key = try keys.read() else { throw PromptAPIError.notConfigured }
                let result = try await PromptAPI.improve("Necesito una presentación de 3 diapositivas sobre ahorro de energía, sin inventar cifras.", preferences: "", key: key, model: model)
                state.record(result)
                status = "Conexión correcta. " + state.lastUsage
            } catch { status = error.localizedDescription }
        }
    }
}
