import CoreGraphics

enum TransformShortcuts {
    // Option + número produce caracteres en muchos layouts de macOS.
    // Control + Command reserva un acorde de comandos sin interceptar esos caracteres.
    static let modifiers: CGEventFlags = [.maskControl, .maskCommand]
    static let keyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    static func index(keyCode: Int, flags: CGEventFlags, count: Int,
                      enabled: Bool, idle: Bool, repeating: Bool) -> Int? {
        let relevant = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn])
        guard enabled, idle, !repeating, relevant == modifiers,
              let index = keyCodes.firstIndex(of: keyCode), index < count else { return nil }
        return index
    }
}
