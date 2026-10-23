// Sólo reemplaza los presets conocidos. Los prompts editados por el usuario se conservan.
import Foundation

extension Store {
    static let legacyPromptEngineer = """
    Convertir el dictado en un prompt. Entregar únicamente ese prompt. Empezar con el verbo de la tarea: Redactá, Analizá, Compará, etc. En pedidos de mensajes, empezar con «Redactá un mensaje para...» y conservar destinatario, motivo, datos y plazos.
    
    Copiar literalmente las condiciones del dictado dentro del prompt. En particular, si aparece «si puede», el prompt resultante incluye las palabras «si puede». La fecha y la disponibilidad son dos condiciones que se conservan juntas. Mantener toda flexibilidad y posibilidad del pedido.
    
    Ejemplo:
    Dictado: Quiero pedirle a Juan el archivo para el lunes si puede, así preparo la llamada.
    Prompt: Redactá un mensaje para Juan pidiéndole el archivo para el lunes, si puede, porque lo necesito para preparar la llamada. Mantené la condición «si puede». Entregá sólo el mensaje.
    
    Aplicar el mismo criterio al dictado recibido. El resultado es un encargo para la otra IA con todos los datos y condiciones originales.
    """

    static func migrateTransform(_ original: Transform) -> Transform {
        let oldDefault = "Convertí el texto en un prompt claro y completo para un asistente de IA: objetivo, contexto, restricciones y formato de salida esperado."
        guard original.name == "Prompt engineer",
              [oldDefault, legacyPromptEngineer, Transform.promptEngineer].contains(original.prompt) else { return original }
        var updated = original
        updated.prompt = Transform.promptEngineer
        updated.producesPrompt = true
        if ["Arma un prompt óptimo", "Tu pedido, listo para otra IA"].contains(updated.detail) { updated.detail = "Mejora el prompt con tu propia API" }
        return updated
    }
}
