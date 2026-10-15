import Cocoa
import Carbon

struct Preset: Codable { var name: String; var x, y, w, h: Double; var keyCode, keyMods: Int; var keyLabel: String }
var presets: [Preset] {   // region as fractions of the screen, so grid-size changes don't move it
    get { defaults.data(forKey: "presets").flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? [] }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "presets"); registerAll(); rebuildPresetMenu(); presetTable.reloadData() }
}
var mainCombo: (code: Int, mods: Int, label: String) {
    (defaults.object(forKey: "keyCode") as? Int ?? kVK_ANSI_D, defaults.object(forKey: "keyMods") as? Int ?? (optionKey | controlKey),
     defaults.string(forKey: "keyLabel") ?? "⌃⌥D")
}
var undoCombo: (code: Int, mods: Int, label: String) {
    (defaults.object(forKey: "undoCode") as? Int ?? kVK_ANSI_Z, defaults.object(forKey: "undoMods") as? Int ?? (optionKey | controlKey),
     defaults.string(forKey: "undoLabel") ?? "⌃⌥Z")
}
func conflict(_ code: Int, _ mods: Int, excluding row: Int? = nil, checkMain: Bool = true, checkUndo: Bool = true) -> String? {
    if checkMain, code == mainCombo.code, mods == mainCombo.mods { return "That shortcut already shows the grid." }
    if checkUndo, code == undoCombo.code, mods == undoCombo.mods { return "That shortcut is Undo." }
    if let p = presets.enumerated().first(where: { $0.offset != row && $0.element.keyCode == code && $0.element.keyMods == mods }) {
        return "That shortcut is used by “\(p.element.name)”."
    }
    return nil
}
var presetSnap: (win: AXUIElement, region: NSRect, pos: CGPoint, size: CGSize)?   // so pressing the same preset again moves on a display
func applyPreset(_ p: Preset) {
    guard let win = pickTarget() else { return }
    let region = NSRect(x: p.x, y: p.y, width: p.w, height: p.h), now = axFrame(win)
    var screen = screenOf(win)
    if let s = presetSnap, let now, CFEqual(s.win, win), s.region == region,
       abs(now.0.x - s.pos.x) <= 2, abs(now.0.y - s.pos.y) <= 2, abs(now.1.width - s.size.width) <= 2, abs(now.1.height - s.size.height) <= 2 {
        screen = nextScreen(after: screen)
    }
    if let now { lastSnap = (win, now.0, now.1) }
    applyFrame(win, screenFrame(fraction: region, on: screen))
    presetSnap = axFrame(win).map { (win, region, $0.0, $0.1) }
    remember(win)
}
func nextScreen(after s: NSScreen) -> NSScreen {   // left to right, top to bottom, wrapping
    let all = NSScreen.screens.sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
    return all[((all.firstIndex(of: s) ?? -1) + 1) % all.count]
}
func alert(_ text: String) { let a = NSAlert(); a.messageText = text; a.runModal() }

func modifierFlags(_ mods: Int) -> NSEvent.ModifierFlags {
    var f: NSEvent.ModifierFlags = []
    if mods & controlKey != 0 { f.insert(.control) }; if mods & optionKey != 0 { f.insert(.option) }
    if mods & shiftKey != 0 { f.insert(.shift) }; if mods & cmdKey != 0 { f.insert(.command) }
    return f
}

func newPreset(_ f: NSRect) {
    NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)   // same reason as showPrefs
    let dialog = NSAlert()
    dialog.messageText = "New preset"
    dialog.addButton(withTitle: "Save"); dialog.addButton(withTitle: "Cancel")
    let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 66))
    let name = NSTextField(frame: NSRect(x: 0, y: 40, width: 260, height: 24))
    name.placeholderString = "Name"; name.stringValue = "Preset \(presets.count + 1)"
    let key = ShortcutButton.make(nil)
    key.frame = NSRect(x: 0, y: 0, width: 260, height: 32)
    box.addSubview(name); box.addSubview(key)
    dialog.accessoryView = box
    dialog.window.initialFirstResponder = name
    while dialog.runModal() == .alertFirstButtonReturn {
        let n = name.stringValue.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { dialog.informativeText = "Give it a name."; continue }
        guard let c = key.combo else { dialog.informativeText = "Record a shortcut."; continue }
        if let why = conflict(c.code, c.mods) { dialog.informativeText = why; continue }
        presets.append(Preset(name: n, x: f.minX, y: f.minY, w: f.width, h: f.height, keyCode: c.code, keyMods: c.mods, keyLabel: c.label))
        break
    }
    key.cancelRecording()   // Cancel mid-recording must not leave every hotkey unregistered
    if !prefs.isVisible { NSApp.hide(nil) }   // give focus back
}
