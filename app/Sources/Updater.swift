// Actualizador propio: consulta la última release en GitHub, descarga el zip, verifica la firma
// contra la de la app en ejecución y reemplaza el bundle con un script que corre tras cerrar la app.

import Cocoa
import SwiftUI
import Security

// Enlaces del proyecto.
enum Links {
    static let repo = "briascoi/hablapp"
    static let site = URL(string: "https://briascoi.github.io/hablapp/")!
    static let github = URL(string: "https://github.com/\(repo)")!
    static let issues = URL(string: "https://github.com/\(repo)/issues/new")!
    static let license = URL(string: "https://github.com/\(repo)/blob/main/LICENSE")!
    static let sponsors: URL? = URL(string: "https://github.com/sponsors/briascoi")
    static let cafecito: URL? = URL(string: "https://cafecito.app/briascoi")
    static let personalSite: URL? = URL(string: "https://ismaelbriasco.com")
    static let linkedin: URL? = URL(string: "https://www.linkedin.com/in/briascoi")
}

struct Release: Equatable {
    let version: String
    let notes: String
    let page: URL
    let zip: URL?
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

final class Updater: ObservableObject {
    static let shared = Updater()
    static let assetName = "hablapp.zip"

    @Published var available: Release?
    @Published var busy = false
    @Published var status = ""

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let preferences: UserDefaults
    private let fetch: () async throws -> Release

    init(preferences: UserDefaults = .standard, fetch: (() async throws -> Release)? = nil) {
        self.preferences = preferences
        self.fetch = fetch ?? Self.fetchLatest
        // Un valor guardado por la persona siempre tiene prioridad sobre el predeterminado.
        preferences.register(defaults: ["autoUpdate": true])
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    static func automaticCheckDue(preferences: UserDefaults, now: Date = Date()) -> Bool {
        guard preferences.object(forKey: "autoUpdate") as? Bool ?? true else { return false }
        guard let last = preferences.object(forKey: "lastUpdateAttempt") as? Date else { return true }
        return now.timeIntervalSince(last) >= 24 * 3600 || last > now
    }

    // MARK: comprobación

    /// `a` es una versión más nueva que `b` (comparación numérica: 0.10.0 > 0.9.1).
    nonisolated static func newer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    /// Chequeo al iniciar (con 10 s de demora) y cada 24 h.
    func startAutomatic() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.check(userInitiated: false)
        }
    }

    func check(userInitiated: Bool) {
        if !userInitiated && !Self.automaticCheckDue(preferences: preferences) { return }
        guard !busy else { return }
        busy = true
        preferences.set(Date(), forKey: "lastUpdateAttempt")
        if userInitiated { status = "Buscando…" }
        Task { @MainActor in
            do {
                let r = try await fetch()
                preferences.set(Date(), forKey: "lastUpdateCheck")
                // Liberar antes de mostrar el diálogo: instalar también comprueba busy.
                busy = false
                if Self.newer(r.version, than: AppInfo.version) {
                    available = r
                    status = "Hay una versión nueva: \(r.version)"
                    if userInitiated { askToInstall(r) }
                } else {
                    available = nil
                    status = "Tienes la última versión (\(AppInfo.version))"
                    if userInitiated { notify("Tienes la última versión", "hablapp \(AppInfo.version) está al día.") }
                }
            } catch {
                busy = false
                status = "No se pudo comprobar la última versión"
                if userInitiated { notify("No se pudo buscar actualizaciones", error.localizedDescription) }
            }
        }
    }

    private struct APIRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    private static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Links.repo)/releases/latest")!)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("hablapp/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHub no devolvió la última versión.") }
        let r = try JSONDecoder().decode(APIRelease.self, from: data)
        let v = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        return Release(version: v, notes: r.body ?? "", page: r.html_url,
                       zip: r.assets.first { $0.name == assetName }?.browser_download_url)
    }

    // MARK: avisos

    private func notify(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "Listo")
        NSApp.activate()
        a.runModal()
    }

    private func askToInstall(_ r: Release) {
        let a = NSAlert()
        a.messageText = "Hay una versión nueva: \(r.version)"
        a.informativeText = "Tienes la \(AppInfo.version). hablapp se reinicia al actualizar."
        a.addButton(withTitle: "Actualizar y reiniciar")
        a.addButton(withTitle: "Más tarde")
        NSApp.activate()
        if a.runModal() == .alertFirstButtonReturn { install(r) }
    }

    // MARK: instalación

    func install(_ r: Release) {
        guard !busy else { return }
        guard Flow.shared.phase == .idle else {
            notify("Termina el dictado antes de actualizar", "Podrás actualizar cuando hablapp termine de procesar tu texto.")
            return
        }
        let bundle = Bundle.main.bundleURL
        // Si no podemos escribir en la carpeta de la app, se actualiza a mano desde la página.
        guard let zip = r.zip, FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            NSWorkspace.shared.open(r.page)
            return
        }
        busy = true
        status = "Descargando \(r.version)…"
        Task { @MainActor in
            defer { busy = false }
            do {
                let new = try await Self.download(zip)
                status = "Verificando…"
                try Self.verifyUpdate(new)
                try Self.launchReplacement(new: new, dest: bundle)
                NSApp.terminate(nil)
            } catch {
                status = "Hay una versión nueva: \(r.version)"
                notify("No se pudo actualizar", error.localizedDescription)
            }
        }
    }

    private static func download(_ zip: URL) async throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hablapp-update")
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let (tmp, resp) = try await URLSession.shared.download(from: zip)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("No se pudo descargar la actualización.") }
        let file = dir.appendingPathComponent("hablapp.zip")
        try fm.moveItem(at: tmp, to: file)
        let out = dir.appendingPathComponent("x")
        try await run("/usr/bin/ditto", ["-x", "-k", file.path, out.path])
        let app = out.appendingPathComponent("hablapp.app")
        guard fm.fileExists(atPath: app.path) else { throw UpdateError("El zip no contiene hablapp.app.") }
        return app
    }

    private static func run(_ exe: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.terminationHandler = { p in
                p.terminationStatus == 0 ? c.resume() : c.resume(throwing: UpdateError("Falló \(exe)."))
            }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
    }

    /// Script en el directorio temporal: espera al PID, copia el nuevo a una ruta hermana, y recién ahí
    /// borra el viejo, mueve y abre. Si la copia falla, el bundle viejo queda intacto y se reabre.
    private static func launchReplacement(new: URL, dest: URL) throws {
        let script = new.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("replace.sh")
        let text = """
        #!/bin/zsh
        PID="$1"; NEW="$2"; DEST="$3"
        while kill -0 $PID 2>/dev/null; do sleep 0.2; done
        TMP="$DEST.update"
        rm -rf "$TMP"
        if /usr/bin/ditto "$NEW" "$TMP"; then
          rm -rf "$DEST"
          mv "$TMP" "$DEST"
        else
          rm -rf "$TMP"
        fi
        /usr/bin/open "$DEST"
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), new.path, dest.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    // MARK: verificación (frontera de seguridad)

    /// La firma del .app cumple el requisito designado de la app en ejecución. Cualquier error lanza.
    nonisolated static func verifySignature(_ app: URL) throws {
        var me: SecCode?
        var meStatic: SecStaticCode?
        var req: SecRequirement?
        var code: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &req) == errSecSuccess, let req,
              SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code
        else { throw UpdateError("No se pudo leer la firma de la actualización.") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess else {
            throw UpdateError("La actualización no está firmada por hablapp.")
        }
    }

    /// Firma válida, mismo bundle id y versión mayor que la actual.
    nonisolated static func verifyUpdate(_ app: URL) throws {
        try verifySignature(app)
        guard let b = Bundle(url: app), b.bundleIdentifier == "com.isma.hablapp" else {
            throw UpdateError("La actualización no es hablapp.")
        }
        let v = b.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard newer(v, than: AppInfo.version) else { throw UpdateError("La actualización no es más nueva que la instalada.") }
    }
}

// MARK: Ajustes › Acerca de

struct AboutSection: View {
    @ObservedObject var up = Updater.shared
    @AppStorage("autoUpdate") var autoUpdate = true

    static let bio = "Soy Ismael Briasco. Llevo más de 25 años en negocios digitales y hoy acompaño a líderes y founders a trabajar con IA. hablapp sirve para dictar en cualquier app sin mandar la voz a la nube, y la comparto como código abierto."

    var body: some View {
        // Cabecera: ícono, nombre y versión, con la actualización al lado.
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("hablapp").font(T.serif(22)).foregroundStyle(T.text)
                Text(up.status.isEmpty ? "Versión \(AppInfo.version)" : "Versión \(AppInfo.version) · \(up.status)")
                    .font(T.sans(12)).foregroundStyle(T.muted)
            }
            Spacer()
            if let r = up.available {
                DarkButton(up.busy ? "Actualizando…" : "Actualizar y reiniciar") { up.install(r) }.disabled(up.busy)
            } else {
                SoftButton(up.busy ? "Buscando…" : "Buscar actualizaciones") { up.check(userInitiated: true) }.disabled(up.busy)
            }
        }
        Group_ {
            if let r = up.available, !r.notes.isEmpty {
                Row("Novedades de \(r.version)", r.notes) { EmptyView() }
            }
            Toggler("Buscar actualizaciones automáticamente", isOn: $autoUpdate)
                .onChange(of: autoUpdate) { _, enabled in if enabled { up.check(userInitiated: false) } }
            Text("Se comprueba al abrir la app o al reactivar el Mac, como máximo una vez al día. Tú decides cuándo instalar y reiniciar.")
                .font(T.sans(12)).foregroundStyle(T.muted).padding(12)
        }

        if Links.sponsors != nil || Links.cafecito != nil {
            Text("Apoyar hablapp").font(T.sans(13, .semibold)).foregroundStyle(T.text)
            Text(SupportReminder.message).font(T.sans(13)).foregroundStyle(T.muted)
            Group_ {
                if let u = Links.sponsors { linkRow("GitHub Sponsors", "Un aporte mensual o único", u) }
                if let u = Links.cafecito { linkRow("Cafecito", "Invítame un café", u) }
                SupportReminderToggle()
            }
        }

        Text("Sobre mí").font(T.sans(13, .semibold)).foregroundStyle(T.text)
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.bio).font(T.sans(13)).foregroundStyle(T.text).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if let u = Links.personalSite { textLink("ismaelbriasco.com", u) }
                if let u = Links.linkedin { textLink("LinkedIn", u) }
                textLink("GitHub", URL(string: "https://github.com/briascoi")!)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(T.panel, in: RoundedRectangle(cornerRadius: 12))

        Text("Proyecto").font(T.sans(13, .semibold)).foregroundStyle(T.text)
        Group_ {
            linkRow("Sitio web", "briascoi.github.io/hablapp", Links.site)
            linkRow("Código fuente", "Abierto, en GitHub", Links.github)
            linkRow("Reportar un problema", "Contanos qué falló", Links.issues)
            linkRow("Licencia", "MIT", Links.license)
        }
    }

    // Fila entera clicable con flecha, como los enlaces de Ajustes del Sistema.
    func linkRow(_ title: String, _ detail: String, _ url: URL) -> some View {
        Row(title, detail) { Image(systemName: "arrow.up.right").font(T.sans(11, .semibold)).foregroundStyle(T.muted) }
            .contentShape(Rectangle())
            .onTapGesture { NSWorkspace.shared.open(url) }
            .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    func textLink(_ title: String, _ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.right").font(T.sans(9, .semibold))
            }.font(T.sans(12, .medium)).foregroundStyle(T.accent)
        }.buttonStyle(.plain)
    }
}
