// VimPanel — NSPanel subclass for hosting the SwiftTerm terminal view.
//
// Overrides canBecomeKey and canBecomeMain to return true so that vim
// receives keyboard input even at .floating window level.
//
// Per Research Pitfall 1: NSPanel defaults for canBecomeKey are context-sensitive
// and unreliable for terminal hosting. Explicit override is required.
// Per Research Pitfall 2: Do NOT add a non-activating style mask —
// it prevents keyboard focus regardless of the canBecomeKey override.
import AppKit

final class VimPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
