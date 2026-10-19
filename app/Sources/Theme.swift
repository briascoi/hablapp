// Tokens visuales (gris cálido, tarjeta clara, títulos con serif,
// botones negros, acento lavanda), con fuentes del sistema (New York + SF).

import SwiftUI

// Versión leída del Info.plist: única fuente para la UI y el actualizador.
enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
}

extension Color {
    init(_ light: UInt32, _ dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { ap in
            let hex = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
    init(hex: UInt32) { self.init(hex, hex) }
}

enum T {
    static let bg = Color(0xF3F1EC, 0x171615)
    static let card = Color(0xFCFBF9, 0x21201E)
    static let panel = Color(0xF3F1ED, 0x2A2927)
    static let line = Color(0xE6E3DD, 0x353431)
    static let text = Color(0x1C1B1A, 0xEDEBE7)
    static let muted = Color(0x77736C, 0x9F9B94)
    static let selected = Color(0xE7E4DE, 0x2E2D2A)
    static let accent = Color(0x7B4FC0, 0xB794F6)
    static let accentSoft = Color(0xEFE7FB, 0x372D48)
    static let teal = Color(0x2F5D62, 0x5E9EA0)
    static let tealSoft = Color(0x8DBCBE, 0x3E6E70)
    static let fn = Color(hex: 0xF4A647)
    static let button = Color(0x1C1B1A, 0xEDEBE7)
    static let buttonText = Color(0xFFFFFF, 0x1C1B1A)

    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

// Botón negro ("Agregar", "Listo").
struct DarkButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(T.sans(13, .medium)).foregroundStyle(T.buttonText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(T.button, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

// Botón gris claro ("Change", "Reset to default").
struct SoftButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(T.sans(13, .medium)).foregroundStyle(T.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(T.selected, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text).font(T.sans(11, .medium)).foregroundStyle(T.accent)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 6))
    }
}

// Tecla dibujada, como el "fn" naranja del saludo o los atajos de Transforms.
struct Key: View {
    let text: String
    var highlight = false
    var body: some View {
        Text(text).font(T.sans(12, .medium)).foregroundStyle(highlight ? Color(hex: 0x2A1A00) : T.text)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(highlight ? T.fn : T.panel, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(highlight ? Color(hex: 0xB86E10) : T.line))
    }
}

// Banner grande con titular en serif. Acá va un degradé propio, sin fotos.
struct Hero<Content: View>: View {
    let title: String
    let subtitle: String
    var colors: [Color] = [Color(hex: 0x2B2420), Color(hex: 0x6B4A33), Color(hex: 0x2F4B4E)]
    var onClose: (() -> Void)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(T.serif(30)).foregroundStyle(.white)
                Text(subtitle).font(T.sans(13)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                content.padding(.top, 6)
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(.white.opacity(0.2), in: Circle())
                }.buttonStyle(.plain).padding(12)
            }
        }
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct HeroChip: View {
    let text: String
    var italic = false
    var body: some View {
        Text(text).font(T.sans(12, .medium)).italic(italic).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct PageTitle<Trailing: View>: View {
    let title: String
    var badge: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(T.serif(26)).foregroundStyle(T.text)
            if let badge { Chip(text: badge) }
            Spacer()
            trailing
        }
    }
}

// Lista con filas separadas por líneas, dentro de un borde redondeado (Diccionario, Snippets, historial).
struct RowList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                row(item)
                if i < items.count - 1 { Divider().overlay(T.line) }
            }
        }
        .background(T.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
    }
}

struct Tabs<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach(tabs, id: \.0) { tab, label in
                    Button { selection = tab } label: {
                        VStack(spacing: 8) {
                            Text(label).font(T.sans(13, selection == tab ? .medium : .regular))
                                .foregroundStyle(selection == tab ? T.text : T.muted)
                            Rectangle().fill(selection == tab ? T.text : .clear).frame(height: 1.5)
                        }.fixedSize()
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            Divider().overlay(T.line)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Buscar"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(T.muted).font(.system(size: 12))
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(T.sans(13))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(T.panel, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 220)
    }
}

// Hoja modal centrada sobre el hub atenuado, como un diálogo modal de macOS.
struct Modal<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var width: CGFloat = 480
    let onClose: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(T.sans(17, .semibold)).foregroundStyle(T.text)
                        if let subtitle { Text(subtitle).font(T.sans(13)).foregroundStyle(T.muted) }
                    }
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(T.muted) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                }
                content
            }
            .padding(22).frame(width: width)
            .background(T.card, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
        }
    }
}

struct Field: View {
    let label: String
    @Binding var text: String
    var multiline = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(T.sans(12, .medium)).foregroundStyle(T.muted)
            Group {
                if multiline {
                    TextEditor(text: $text).font(T.sans(13)).scrollContentBackground(.hidden).frame(height: 110)
                } else {
                    TextField("", text: $text).textFieldStyle(.plain).font(T.sans(13))
                }
            }
            .padding(8).background(T.panel, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
