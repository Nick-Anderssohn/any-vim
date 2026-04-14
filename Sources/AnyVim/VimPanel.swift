// VimPanel — NSPanel subclass for hosting the SwiftTerm terminal view.
//
// Overrides canBecomeKey and canBecomeMain to return true so that vim
// receives keyboard input even at .floating window level.
//
// Per Research Pitfall 1: NSPanel defaults for canBecomeKey are context-sensitive
// and unreliable for terminal hosting. Explicit override is required.
// Per Research Pitfall 2: Do NOT add a non-activating style mask —
// it prevents keyboard focus regardless of the canBecomeKey override.
//
// performKeyEquivalent bridges Cmd+V/C/A/X to the SwiftTerm responder chain.
// AnyVim has no main menu (LSUIElement / .accessory policy), so AppKit never
// resolves these shortcuts through NSApp.mainMenu. By intercepting them here
// and calling NSApp.sendAction(_:to:nil), we let SwiftTerm's paste:/copy:/
// selectAll:/cut: implementations handle them correctly.
import AppKit

final class VimPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Map of lowercased characters (Command-only) → Edit selectors.
    private static let editSelectors: [String: Selector] = [
        "v": #selector(NSText.paste(_:)),
        "c": #selector(NSText.copy(_:)),
        "a": #selector(NSText.selectAll(_:)),
        "x": #selector(NSText.cut(_:)),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let onlyCommand = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask) == .command

        guard event.type == .keyDown, onlyCommand else {
            return super.performKeyEquivalent(with: event)
        }

        return event.charactersIgnoringModifiers
            .flatMap { VimPanel.editSelectors[$0.lowercased()] }
            .map { selector in
                firstResponder?.tryToPerform(selector, with: self) ?? false
            }
            ?? super.performKeyEquivalent(with: event)
    }
}
