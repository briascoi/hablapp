// La barra flotante: una píldora negra abajo al centro que nunca roba el foco.
// Reposo: rayita. Hover: invita a dictar. Grabando: onda en vivo. Manos libres: cancelar y parar.

import Cocoa
import SwiftUI

final class FlowBar {
    private let panel: NSPanel
    private let size = NSSize(width: 340, height: 64)
    private var monitors: [Any] = []

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: FlowBarView())
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        place()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place() }
        // Hover: la ventana es transparente y deja pasar los clics salvo cuando el mouse está sobre la píldora.
        let check: (NSEvent?) -> Void = { [weak self] _ in self?.trackMouse() }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: check) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { check($0); return $0 } as Any)
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    func place() {
        guard let vf = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 6))
    }

    private func trackMouse() {
        let p = NSEvent.mouseLocation
        if !panel.frame.contains(p), screen?.frame.contains(panel.frame.origin) == false { place() }
        let pill = NSRect(x: panel.frame.midX - 110, y: panel.frame.minY, width: 220, height: 44)
        let over = pill.contains(p)
        let flow = Flow.shared
        if over != flow.hovering {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { flow.hovering = over }
        }
        panel.ignoresMouseEvents = !over
    }
}

struct FlowBarView: View {
    @ObservedObject var flow = Flow.shared
    @AppStorage("showFlowBar") var always = true

    var body: some View {
        VStack {
            Spacer()
            pill
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: flow.phase)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: flow.hovering)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
    }

    @ViewBuilder var pill: some View {
        switch flow.phase {
        case .idle:
            if flow.hovering {
                Button { Engine.shared.toggleHandsFree() } label: {
                    HStack(spacing: 6) {
                        Text("Clic o mantené").foregroundStyle(.white.opacity(0.75))
                        Text("fn").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x2A1A00))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(hex: 0xF4A647), in: RoundedRectangle(cornerRadius: 4))
                        Text("para dictar").foregroundStyle(.white.opacity(0.75))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(capsule)
                }.buttonStyle(.plain)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Capsule().fill(.black.opacity(0.82))
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                    .frame(width: 42, height: 8)
                    .opacity(always ? 1 : 0)
            }
        case .recording(let handsFree, let command):
            HStack(spacing: 10) {
                if handsFree {
                    circleButton("xmark", bg: .white.opacity(0.18)) { Engine.shared.cancel(silent: false) }
                }
                Wave(levels: flow.levels, color: command ? Color(hex: 0xC4A5FF) : .white)
                if handsFree {
                    Button { Engine.shared.toggleHandsFree() } label: {
                        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 8, height: 8)
                            .frame(width: 22, height: 22).background(Color(hex: 0xE5484D), in: Circle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, handsFree ? 6 : 16).frame(height: 34)
            .background(capsule)
            .overlay(command ? Capsule().stroke(Color(hex: 0xB794F6).opacity(0.8), lineWidth: 1.5) : nil)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .processing(let command):
            Dots(color: command ? Color(hex: 0xC4A5FF) : .white)
                .padding(.horizontal, 18).frame(height: 34)
                .background(capsule)
        case .notice(let text):
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 32)
                .background(capsule)
                .transition(.opacity)
        }
    }

    var capsule: some View {
        Capsule().fill(.black.opacity(0.9)).overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    func circleButton(_ icon: String, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(bg, in: Circle())
        }.buttonStyle(.plain)
    }
}

struct Wave: View {
    let levels: [Float]
    var color: Color = .white
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { i, l in
                // Más alto al centro, como una onda de voz.
                let shape = 1 - abs(Double(i) - Double(levels.count - 1) / 2) / Double(levels.count)
                Capsule().fill(color)
                    .frame(width: 3, height: max(4, CGFloat(Double(l) * 22 * (0.5 + shape))))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

struct Dots: View {
    var color: Color = .white
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle().fill(color).frame(width: 5, height: 5)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.7)))
                }
            }
        }
    }
}
