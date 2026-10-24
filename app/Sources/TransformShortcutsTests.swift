import CoreGraphics

func transformShortcutsTests(_ check: (String, Bool) -> Void) {
    func index(_ code: Int, _ flags: CGEventFlags, count: Int = 9,
               enabled: Bool = true, idle: Bool = true, repeating: Bool = false) -> Int? {
        TransformShortcuts.index(keyCode: code, flags: flags, count: count,
                                 enabled: enabled, idle: idle, repeating: repeating)
    }
    let codes = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    for (i, code) in codes.enumerated() {
        check("atajos: Control + Command + \(i + 1) selecciona el transform", index(code, [.maskControl, .maskCommand]) == i)
    }
    // Recorre todas las teclas: Option solo o con Shift debe llegar intacto a la app destino.
    for flags: CGEventFlags in [[], .maskShift, .maskAlternate, [.maskAlternate, .maskShift]] {
        check("atajos: escritura intacta con modificadores \(flags.rawValue)",
              (0..<128).allSatisfy { index($0, flags) == nil })
    }
    check("atajos: Command sin Control no activa", index(18, .maskCommand) == nil)
    check("atajos: Control sin Command no activa", index(18, .maskControl) == nil)
    check("atajos: modificadores adicionales no activan",
          [CGEventFlags.maskAlternate, .maskShift, .maskSecondaryFn].allSatisfy {
              index(18, TransformShortcuts.modifiers.union($0)) == nil
          })
    check("atajos: Bloq Mayús no altera el acorde", index(18, [.maskControl, .maskCommand, .maskAlphaShift]) == 0)
    check("atajos: desactivados no capturan", index(18, TransformShortcuts.modifiers, enabled: false) == nil)
    check("atajos: grabando o procesando no capturan", index(18, TransformShortcuts.modifiers, idle: false) == nil)
    check("atajos: repetición no vuelve a ejecutar", index(18, TransformShortcuts.modifiers, repeating: true) == nil)
    check("atajos: lista vacía no captura", index(18, TransformShortcuts.modifiers, count: 0) == nil)
    check("atajos: posición inexistente no captura", index(21, TransformShortcuts.modifiers, count: 3) == nil)
    check("atajos: cero no captura", index(29, TransformShortcuts.modifiers) == nil)
    check("atajos: letras no capturan", index(0, TransformShortcuts.modifiers) == nil)
}
