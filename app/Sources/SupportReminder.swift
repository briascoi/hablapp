import SwiftUI

/// Estado local del recordatorio. No consulta donantes ni guarda datos de pagos.
final class SupportReminder: ObservableObject {
    static let shared = SupportReminder()
    static let message = "Tu aporte ayuda a Ismael Briasco a seguir creando software de código abierto y a mantener Hablapp. Donar es opcional."
    static let month: TimeInterval = 30 * 86400
    private let preferences: UserDefaults
    @Published private(set) var visible = false

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        preferences.register(defaults: ["supportReminders": true])
    }

    func bootstrap(history: [Entry], now: Date = Date()) {
        if preferences.object(forKey: "support.firstUse") == nil {
            let dictations = history.filter { $0.kind == "dictado" && $0.words > 0 }
            preferences.set(dictations.map(\.date).min() ?? now, forKey: "support.firstUse")
            preferences.set(dictations.count, forKey: "support.dictations")
        }
        refresh(now: now)
    }

    func recordDictation(now: Date = Date()) {
        if preferences.object(forKey: "support.firstUse") == nil { bootstrap(history: [], now: now) }
        preferences.set(preferences.integer(forKey: "support.dictations") + 1, forKey: "support.dictations")
        refresh(now: now)
    }

    func refresh(now: Date = Date()) {
        guard preferences.bool(forKey: "supportReminders"),
              let first = preferences.object(forKey: "support.firstUse") as? Date,
              now.timeIntervalSince(first) >= 7 * 86400,
              preferences.integer(forKey: "support.dictations") >= 20 else {
            visible = false
            return
        }
        let next = preferences.object(forKey: "support.nextReminder") as? Date ?? .distantPast
        visible = now >= next
    }

    func later(now: Date = Date()) {
        preferences.set(now.addingTimeInterval(Self.month), forKey: "support.nextReminder")
        refresh(now: now)
    }

    func disable() {
        preferences.set(false, forKey: "supportReminders")
        refresh()
    }
}

struct SupportReminderToggle: View {
    @AppStorage("supportReminders") private var enabled = true
    var body: some View {
        Toggler("Recordarme que puedo apoyar el proyecto", isOn: $enabled)
            .onChange(of: enabled) { _, _ in SupportReminder.shared.refresh() }
    }
}

struct SupportReminderCard: View {
    @ObservedObject var reminder = SupportReminder.shared
    @ObservedObject var flow = Flow.shared
    var body: some View {
        if reminder.visible && flow.phase == .idle {
            VStack(alignment: .leading, spacing: 12) {
                Label("¿Hablapp te resulta útil?", systemImage: "heart").font(T.sans(15, .semibold))
                Text(SupportReminder.message).font(T.sans(13)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    DarkButton("Apoyar en GitHub") {
                        if let url = Links.sponsors, NSWorkspace.shared.open(url) { reminder.later() }
                    }
                    SoftButton("Más adelante") { reminder.later() }
                    Button("No recordar") { reminder.disable() }.buttonStyle(.plain).font(T.sans(12))
                }
                Button("Ya apoyo el proyecto") { reminder.disable() }
                    .buttonStyle(.plain).font(T.sans(12)).foregroundStyle(T.muted)
            }
            .foregroundStyle(T.text).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct UpdateBanner: View {
    @ObservedObject var updater = Updater.shared
    @ObservedObject var flow = Flow.shared
    var body: some View {
        if let release = updater.available {
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.circle").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hablapp \(release.version) está disponible").font(T.sans(14, .semibold))
                    Text(updater.busy ? updater.status : "Actualiza cuando termines de dictar. La app se reiniciará.")
                        .font(T.sans(12))
                }
                Spacer()
                DarkButton(updater.busy ? "Actualizando…" : "Actualizar y reiniciar") { updater.install(release) }
                    .disabled(updater.busy || flow.phase != .idle)
            }
            .foregroundStyle(T.text).padding(16)
            .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
