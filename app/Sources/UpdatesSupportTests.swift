import Foundation

func updatesSupportTests(_ check: (String, Bool) -> Void) {
    let suite = "hablapp-support-tests-" + UUID().uuidString
    let prefs = UserDefaults(suiteName: suite)!
    defer { prefs.removePersistentDomain(forName: suite) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reminder = SupportReminder(preferences: prefs)
    reminder.bootstrap(history: [], now: now)
    check("donación: instalación nueva sin aviso", !reminder.visible)
    for _ in 0..<20 { reminder.recordDictation(now: now) }
    check("donación: veinte dictados no saltean los siete días", !reminder.visible)
    let week = now.addingTimeInterval(7 * 86400)
    reminder.refresh(now: week)
    check("donación: siete días y veinte dictados habilitan aviso", reminder.visible)
    reminder.later(now: week)
    let restored = SupportReminder(preferences: prefs)
    restored.refresh(now: week.addingTimeInterval(SupportReminder.month - 1))
    check("donación: posponer persiste tras reinicio", !restored.visible)
    restored.refresh(now: week.addingTimeInterval(SupportReminder.month))
    check("donación: vuelve a los treinta días", restored.visible)
    restored.disable()
    restored.refresh(now: week.addingTimeInterval(365 * 86400))
    check("donación: desactivar no caduca", !restored.visible)
    prefs.set(true, forKey: "supportReminders")
    restored.refresh(now: week.addingTimeInterval(SupportReminder.month))
    check("donación: se puede reactivar en ajustes", restored.visible)
    prefs.set(19, forKey: "support.dictations")
    restored.refresh(now: week.addingTimeInterval(SupportReminder.month))
    check("donación: no aparece con diecinueve dictados", !restored.visible)

    var fetches = 0
    let release = Release(version: "999.0.0", notes: "Prueba", page: Links.github, zip: nil)
    let updater = Updater(preferences: prefs, fetch: { fetches += 1; return release })
    check("actualizaciones: activadas por defecto", prefs.bool(forKey: "autoUpdate"))
    check("actualizaciones: primera búsqueda pendiente", Updater.automaticCheckDue(preferences: prefs, now: now))
    prefs.set(now, forKey: "lastUpdateAttempt")
    check("actualizaciones: limita frecuencia entre reinicios", !Updater.automaticCheckDue(preferences: prefs, now: now.addingTimeInterval(86399)))
    check("actualizaciones: vuelve al cumplir 24 horas", Updater.automaticCheckDue(preferences: prefs, now: now.addingTimeInterval(86400)))
    check("actualizaciones: recupera reloj atrasado", Updater.automaticCheckDue(preferences: prefs, now: now.addingTimeInterval(-1)))
    prefs.set(false, forKey: "autoUpdate")
    _ = Updater(preferences: prefs)
    updater.check(userInitiated: false)
    check("actualizaciones: conserva desactivación y no consulta red", !prefs.bool(forKey: "autoUpdate") && fetches == 0 && !updater.busy)
    prefs.set(true, forKey: "autoUpdate")
    prefs.removeObject(forKey: "lastUpdateAttempt")
    updater.check(userInitiated: false)
    updater.check(userInitiated: false)
    let deadline = Date().addingTimeInterval(3)
    while updater.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check("actualizaciones: publica versión disponible y libera ocupado", updater.available == release && !updater.busy)
    check("actualizaciones: evita solicitudes simultáneas", fetches == 1)
    check("actualizaciones: registra comprobación exitosa", prefs.object(forKey: "lastUpdateCheck") is Date)
    prefs.removeObject(forKey: "lastUpdateAttempt")
    let failing = Updater(preferences: prefs, fetch: { throw UpdateError("Sin conexión de prueba") })
    failing.check(userInitiated: false)
    let errorDeadline = Date().addingTimeInterval(3)
    while failing.busy && Date() < errorDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check("actualizaciones: fallo de red libera ocupado y muestra estado", !failing.busy && failing.status.contains("No se pudo"))
}
