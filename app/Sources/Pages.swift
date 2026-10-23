// Inicio (historial + números) y Estadísticas.

import SwiftUI

let es = Locale(identifier: "es_AR")

struct HomePage: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var perms = Perms.shared
    @AppStorage("userName") var userName = ""
    @AppStorage("hero.home") var heroClosed = false
    @State var query = ""
    @State var searching = false

    var name: String {
        userName.isEmpty ? (NSFullUserName().components(separatedBy: " ").first ?? "") : userName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                Text(name.isEmpty ? "Volvé al flow con" : "Hola \(name), volvé al flow con").font(T.serif(28)).foregroundStyle(T.text)
                Key(text: "fn", highlight: true).scaleEffect(1.25)
            }
            SupportReminderCard()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 26) {
                    if !perms.allGood { PermissionsCard() }
                    if !heroClosed {
                        Hero(title: "Hablá en cualquier app",
                             subtitle: "Mantené fn, hablá y soltá: el texto aparece donde está el cursor, con puntuación y en el tono de cada app.",
                             onClose: { heroClosed = true }) {
                            Button { HubState.shared.shortcuts = true } label: {
                                Text("Ver atajos").font(T.sans(13, .medium)).foregroundStyle(Color(hex: 0x1C1B1A))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Color(hex: 0xF6F3EE), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                    history
                }
                StatsCard().frame(width: 250)
            }
        }
        .onAppear { SupportReminder.shared.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            SupportReminder.shared.refresh()
        }
    }

    var filtered: [Entry] {
        let base = store.history.filter { !$0.text.isEmpty }
        guard !query.isEmpty else { return Array(base.prefix(300)) }
        return base.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder var history: some View {
        let days = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
        let keys = days.keys.sorted(by: >)
        VStack(alignment: .leading, spacing: 12) {
            if keys.isEmpty {
                HStack {
                    Text(query.isEmpty ? "HISTORIAL" : "SIN RESULTADOS").font(T.sans(11, .medium)).tracking(1).foregroundStyle(T.muted)
                    Spacer()
                    searchToggle
                }
                if query.isEmpty {
                    Text("Todavía no dictaste nada. Mantené fn en cualquier app, hablá y soltá.")
                        .font(T.sans(14)).foregroundStyle(T.muted).padding(.vertical, 30).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(keys.enumerated()), id: \.element) { i, day in
                HStack {
                    Text(day.formatted(.dateTime.day().month(.wide).year().locale(es)).uppercased())
                        .font(T.sans(11, .medium)).tracking(1).foregroundStyle(T.muted)
                    Spacer()
                    if i == 0 { searchToggle }
                }
                .padding(.top, i == 0 ? 0 : 12)
                RowList(items: days[day] ?? []) { HistoryRow(entry: $0) }
            }
        }
    }

    @ViewBuilder var searchToggle: some View {
        if searching {
            SearchField(text: $query, placeholder: "Buscar en el historial")
        } else {
            Button { searching = true } label: { Image(systemName: "magnifyingglass").foregroundStyle(T.muted) }.buttonStyle(.plain)
        }
    }
}

struct HistoryRow: View {
    let entry: Entry
    @State var hover = false
    @State var showRaw = false

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(entry.date.formatted(.dateTime.hour().minute().locale(es)))
                .font(T.sans(12)).foregroundStyle(T.muted).frame(width: 64, alignment: .leading).padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text).font(T.sans(14)).foregroundStyle(T.text).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if showRaw {
                    Text("Crudo: \(entry.raw)").font(T.sans(12)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                }
                if hover {
                    HStack(spacing: 10) {
                        if !entry.app.isEmpty { Text(entry.app).font(T.sans(11)).foregroundStyle(T.muted) }
                        if entry.kind != "dictado" { Chip(text: entry.kind) }
                    }
                }
            }
            Spacer()
            if hover {
                HStack(spacing: 12) {
                    icon("doc.on.doc", "Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    }
                    if entry.raw != entry.text { icon("text.magnifyingglass", "Ver crudo") { showRaw.toggle() } }
                    icon("trash", "Borrar") { Store.shared.history.removeAll { $0.id == entry.id } }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(hover ? T.panel.opacity(0.5) : .clear)
        .onHover { hover = $0 }
    }

    func icon(_ name: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 12)).foregroundStyle(T.muted) }
            .buttonStyle(.plain).help(help)
    }
}

struct StatsCard: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                stat(store.totalWords, "palabras en total")
                stat(store.wpm, "palabras por minuto")
                stat(store.streak, store.streak == 1 ? "día seguido" : "días seguidos")
            }.padding(20)
            Divider().overlay(T.line)
            VStack(alignment: .leading, spacing: 8) {
                Text("Desafío de 100 palabras por día").font(T.sans(14, .medium)).foregroundStyle(T.text)
                Text("Dictá 100 palabras hoy para sumar a tu racha.").font(T.sans(12)).foregroundStyle(T.muted)
                HStack(spacing: 8) {
                    ProgressBar(value: Double(min(store.wordsToday, 100)) / 100)
                    Text("\(min(store.wordsToday, 100))/100").font(T.sans(11)).foregroundStyle(T.muted)
                }
            }.padding(20)
            Divider().overlay(T.line)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tu última transcripción").font(T.sans(14, .medium)).foregroundStyle(T.text)
                HStack(spacing: 4) {
                    Key(text: "⌃"); Key(text: "⌘"); Key(text: "V")
                    Text("la vuelve a pegar").font(T.sans(12)).foregroundStyle(T.muted)
                }
            }.padding(20)
        }
        .background(T.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.line))
    }

    func stat(_ n: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(n.formatted(.number.locale(es))).font(T.serif(26)).foregroundStyle(T.text)
            Text(label).font(T.sans(13)).foregroundStyle(T.text)
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var color = T.accent
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(T.line)
                Capsule().fill(color).frame(width: max(6, g.size.width * value))
            }
        }.frame(height: 6)
    }
}

struct PermissionsCard: View {
    @ObservedObject var perms = Perms.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Para dictar en cualquier app, hablapp necesita dos permisos").font(T.sans(15, .semibold)).foregroundStyle(T.text)
            perm("Micrófono", "Para escucharte mientras mantenés fn.", perms.mic)
            perm("Accesibilidad", "Para detectar fn, leer el contexto del cursor y pegar el texto.", perms.accessibility)
            DarkButton("Configurar paso a paso") { Onboarding.shared.show() }
        }
        .padding(18)
        .background(Color(0xFFF4E5, 0x3A2E1E), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(0xF2D3A6, 0x5C4626)))
    }

    func perm(_ title: String, _ detail: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? T.teal : T.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(T.sans(13, .medium)).foregroundStyle(T.text)
                Text(detail).font(T.sans(12)).foregroundStyle(T.muted)
            }
            Spacer()
        }
    }
}

// MARK: Estadísticas

struct InsightsPage: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: "Estadísticas") { EmptyView() }
            HStack(alignment: .top, spacing: 16) {
                card {
                    big(store.wpm, "Palabras por minuto")
                    Gauge(value: Double(store.wpm) / 200).frame(height: 70).padding(.top, 6)
                }
                card {
                    big(store.fixes, "Correcciones de tu diccionario")
                    Divider().overlay(T.line)
                    Text("\(store.words.filter(\.isReplacement).count) reemplazos y \(store.words.filter { !$0.isReplacement }.count) palabras guardadas")
                        .font(T.sans(12)).foregroundStyle(T.muted)
                }
                card {
                    big(store.totalWords, "Palabras dictadas")
                    Divider().overlay(T.line)
                    HStack {
                        Image(systemName: "desktopcomputer")
                        Text("\(store.dictations.count) dictados · \(store.history.filter { $0.kind != "dictado" }.count) comandos y transforms")
                    }.font(T.sans(12)).foregroundStyle(T.muted)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                card {
                    HStack {
                        Text("Uso por tipo de app").font(T.serif(22)).foregroundStyle(T.text)
                        Spacer()
                        Text("APPS USADAS | \(Set(store.dictations.map(\.app)).count)").font(T.sans(11, .medium)).foregroundStyle(T.muted)
                    }
                    ForEach(store.usage(), id: \.0) { cat, pct in
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon).frame(width: 18).foregroundStyle(T.text)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(T.tealSoft.opacity(0.35))
                                    RoundedRectangle(cornerRadius: 3).fill(T.teal).frame(width: max(28, g.size.width * Double(pct) / 100))
                                    Text("\(pct)%").font(T.sans(10, .medium)).foregroundStyle(.white).padding(.leading, 6)
                                }
                            }.frame(width: 110, height: 18)
                            Text(cat.title.uppercased()).font(T.sans(11, .medium)).foregroundStyle(T.text)
                        }
                    }
                }
                card {
                    HStack {
                        Text("Racha de \(store.streak) \(store.streak == 1 ? "día" : "días")").font(T.serif(22)).foregroundStyle(T.text)
                        Spacer()
                        Text("RACHA MÁS LARGA | \(store.longestStreak)").font(T.sans(11, .medium)).foregroundStyle(T.muted)
                    }
                    Heatmap(days: store.wordsByDay)
                }
            }
        }
    }

    func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { c() }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(T.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    func big(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(n.formatted(.number.locale(es))).font(T.serif(30)).foregroundStyle(T.text)
            Text(label.uppercased()).font(T.sans(10, .medium)).tracking(0.8).foregroundStyle(T.muted)
        }
    }
}

struct Gauge: View {
    let value: Double
    var body: some View {
        ZStack {
            Arc(to: 1).stroke(T.line, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            Arc(to: min(max(value, 0.02), 1)).stroke(T.teal, style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
        .frame(width: 130, height: 65).padding(.top, 6).frame(maxWidth: .infinity)
    }
}

/// Semicírculo de izquierda a derecha, apoyado en el borde inferior; `to` es la fracción dibujada.
struct Arc: Shape {
    let to: Double
    func path(in r: CGRect) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: r.midX, y: r.maxY), radius: r.width / 2,
                     startAngle: .degrees(180), endAngle: .degrees(180 + 180 * to), clockwise: false)
        }
    }
}

struct Heatmap: View {
    let days: [Date: Int]
    let weeks = 18

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart)!
        let names = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(names[(d + cal.firstWeekday - 1) % 7]).font(T.sans(9)).foregroundStyle(T.muted).frame(height: 11)
                    }
                }
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            RoundedRectangle(cornerRadius: 2).fill(color(day > today ? nil : (days[day] ?? 0)))
                                .frame(width: 11, height: 11)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Menos").font(T.sans(10)).foregroundStyle(T.muted)
                ForEach([0, 10, 60, 200], id: \.self) { RoundedRectangle(cornerRadius: 2).fill(color($0)).frame(width: 10, height: 10) }
                Text("Más").font(T.sans(10)).foregroundStyle(T.muted)
            }
        }
    }

    func color(_ words: Int?) -> Color {
        guard let words else { return .clear }
        switch words {
        case 0: return T.line
        case ..<30: return T.tealSoft.opacity(0.6)
        case ..<120: return T.tealSoft
        default: return T.teal
        }
    }
}
