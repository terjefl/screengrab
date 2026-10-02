import AppKit
import Carbon

enum CaptureMode: String, CaseIterable {
    // Rekkefølgen følger standardtastene ⌘⇧1/2/3 (meny og innstillinger).
    case clipboard, edit, save

    var title: String {
        switch self {
        case .save: return "Ta område → lagre i mappen"
        case .edit: return "Ta område → åpne for tegning"
        case .clipboard: return "Ta område → utklippstavlen"
        }
    }

    var hotkeyID: UInt32 {
        switch self {
        case .save: return 1
        case .edit: return 2
        case .clipboard: return 3
        }
    }

    var defaultHotkey: Hotkey {
        let m = UInt32(cmdKey | shiftKey)
        switch self {
        case .clipboard: return Hotkey(keyCode: UInt32(kVK_ANSI_1), modifiers: m, key: "1")
        case .edit: return Hotkey(keyCode: UInt32(kVK_ANSI_2), modifiers: m, key: "2")
        case .save: return Hotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: m, key: "3")
        }
    }
}

/// Hva «Lagre»-knappen (⌘S) gjør i tegnevinduet.
enum SaveBehavior: String, CaseIterable {
    case saveClose, save

    var title: String {
        switch self {
        case .saveClose: return "Lagre og lukk"
        case .save: return "Lagre (vinduet blir stående)"
        }
    }

    var buttonTitle: String { self == .saveClose ? "Lagre og lukk" : "Lagre" }
}

/// Hva «Kopier»-knappen (⌘C / ↩) gjør i tegnevinduet.
enum CopyBehavior: String, CaseIterable {
    case copySaveClose, copyClose, copy

    var title: String {
        switch self {
        case .copySaveClose: return "Kopier, lagre og lukk"
        case .copyClose: return "Kopier og lukk"
        case .copy: return "Kopier (vinduet blir stående)"
        }
    }

    var buttonTitle: String {
        switch self {
        case .copySaveClose: return "Kopier, lagre og lukk"
        case .copyClose: return "Kopier og lukk"
        case .copy: return "Kopier"
        }
    }
}

extension Notification.Name {
    static let hotkeysChanged = Notification.Name("screengrab.hotkeysChanged")
    static let hotkeyRecording = Notification.Name("screengrab.hotkeyRecording")
    static let behaviorChanged = Notification.Name("screengrab.behaviorChanged")
}

/// macOS sine egne skjermbildesnarveier. Er de på, tar systemet tastetrykket før screengrab ser det.
enum SystemShortcuts {
    struct Entry {
        let id: Int
        let hotkey: Hotkey
        let name: String
    }

    private static let cs = UInt32(cmdKey | shiftKey), ccs = UInt32(cmdKey | shiftKey | controlKey)
    static let screenshot: [Entry] = [
        Entry(id: 28, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: cs, key: "3"),
              name: "Arkiver bilde av skjermen som en fil"),
        Entry(id: 29, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: ccs, key: "3"),
              name: "Kopier bilde av skjermen til utklippstavlen"),
        Entry(id: 30, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: cs, key: "4"),
              name: "Arkiver bilde av markert område som en fil"),
        Entry(id: 31, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: ccs, key: "4"),
              name: "Kopier bilde av markert område til utklippstavlen"),
        Entry(id: 184, hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_5), modifiers: cs, key: "5"),
              name: "Valg for skjermbilder og opptak"),
    ]

    /// Navnet på macOS-snarveien som bruker samme kombinasjon, hvis den er slått på.
    static func conflict(for hk: Hotkey) -> String? {
        let prefs = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                              "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        for e in screenshot {
            var keyCode = e.hotkey.keyCode, mods = e.hotkey.modifiers, enabled = true
            if let entry = prefs?[String(e.id)] as? [String: Any] {
                if let en = entry["enabled"] { enabled = (en as? Bool) ?? ((en as? Int ?? 1) != 0) }
                // Brukeren kan ha flyttet snarveien: parameters = [tegn, tastekode, Cocoa-modifikatorer].
                if let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3 {
                    keyCode = UInt32(params[1])
                    mods = carbonModifiers(cocoa: params[2])
                }
            }
            if enabled, keyCode == hk.keyCode, mods == hk.modifiers { return e.name }
        }
        return nil
    }

    private static func carbonModifiers(cocoa: Int) -> UInt32 {
        var m: UInt32 = 0
        if cocoa & (1 << 17) != 0 { m |= UInt32(shiftKey) }
        if cocoa & (1 << 18) != 0 { m |= UInt32(controlKey) }
        if cocoa & (1 << 19) != 0 { m |= UInt32(optionKey) }
        if cocoa & (1 << 20) != 0 { m |= UInt32(cmdKey) }
        return m
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static let howToDisable = "Slå den av i Systeminnstillinger → Tastatur → Tastatursnarveier… → Skjermbilder."
}

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    /// Standard: samme mappe som macOS lagrer skjermbilder i (Skjermbilde-appen → Valg → Arkiver i),
    /// ellers Skrivebordet.
    static var defaultFolder: String {
        let macOS = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
        if let macOS, !macOS.isEmpty { return macOS }
        return "~/Desktop"
    }

    var folder: URL {
        get {
            let path = defaults.string(forKey: "folder") ?? Settings.defaultFolder
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        set {
            let home = NSHomeDirectory()
            var p = newValue.path
            if p.hasPrefix(home) { p = "~" + p.dropFirst(home.count) }
            defaults.set(p, forKey: "folder")
        }
    }

    var saveBehavior: SaveBehavior {
        get { SaveBehavior(rawValue: defaults.string(forKey: "saveBehavior") ?? "") ?? .saveClose }
        set {
            defaults.set(newValue.rawValue, forKey: "saveBehavior")
            NotificationCenter.default.post(name: .behaviorChanged, object: nil)
        }
    }

    var copyBehavior: CopyBehavior {
        get { CopyBehavior(rawValue: defaults.string(forKey: "copyBehavior") ?? "") ?? .copySaveClose }
        set {
            defaults.set(newValue.rawValue, forKey: "copyBehavior")
            NotificationCenter.default.post(name: .behaviorChanged, object: nil)
        }
    }

    /// nil = hurtigtasten er slått av. Ingen lagret verdi = standard.
    func hotkey(for mode: CaptureMode) -> Hotkey? {
        let k = "hotkey.\(mode.rawValue)"
        guard let data = defaults.data(forKey: k) else {
            return defaults.bool(forKey: k + ".off") ? nil : mode.defaultHotkey
        }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    func setHotkey(_ hk: Hotkey?, for mode: CaptureMode) {
        let k = "hotkey.\(mode.rawValue)"
        if let hk, let data = try? JSONEncoder().encode(hk) {
            defaults.set(data, forKey: k)
            defaults.removeObject(forKey: k + ".off")
        } else {
            defaults.removeObject(forKey: k)
            defaults.set(true, forKey: k + ".off")
        }
        NotificationCenter.default.post(name: .hotkeysChanged, object: nil)
    }

    func resetHotkey(for mode: CaptureMode) {
        let k = "hotkey.\(mode.rawValue)"
        defaults.removeObject(forKey: k)
        defaults.removeObject(forKey: k + ".off")
        NotificationCenter.default.post(name: .hotkeysChanged, object: nil)
    }

    /// Hurtigtaster som kolliderer med en påslått macOS-snarvei: (modus, tast, navn på macOS-snarveien).
    func systemConflicts() -> [(mode: CaptureMode, hotkey: Hotkey, name: String)] {
        CaptureMode.allCases.compactMap { mode in
            guard let hk = hotkey(for: mode), let name = SystemShortcuts.conflict(for: hk) else { return nil }
            return (mode, hk, name)
        }
    }

    /// «Skjermbilde 2026-10-01 kl. 08.20.15.png» i mappen, med « (2)» osv. ved kollisjon.
    func newScreenshotURL(base: String? = nil, in dir: URL? = nil) -> URL {
        let dir = dir ?? folder
        let name: String
        if let base {
            name = base
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "nb_NO")
            f.dateFormat = "yyyy-MM-dd 'kl.' HH.mm.ss"
            name = "Skjermbilde \(f.string(from: Date()))"
        }
        var url = dir.appendingPathComponent(name + ".png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(name) (\(n)).png")
            n += 1
        }
        return url
    }

    func ensureFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Nyeste bilde i mappen (for «Tegn på siste skjermbilde»).
    func newestImage() -> URL? {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        let exts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        return items
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .compactMap { u -> (URL, Date)? in
                guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
                return (u, v.creationDate ?? .distantPast)
            }
            .max { $0.1 < $1.1 }?.0
    }
}

// MARK: - Innstillingsvindu

final class HotkeyRecorder: NSButton {
    var hotkey: Hotkey? { didSet { refreshTitle() } }
    var onChange: ((Hotkey?) -> Void)?
    private var monitor: Any?

    convenience init(hotkey: Hotkey?) {
        self.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggle)
        self.hotkey = hotkey
        refreshTitle()
        widthAnchor.constraint(equalToConstant: 170).isActive = true
    }

    private func refreshTitle() {
        title = monitor != nil ? "Trykk kombinasjon…" : (hotkey?.display ?? "Av")
    }

    @objc private func toggle() { monitor == nil ? start() : stop() }

    private func start() {
        NotificationCenter.default.post(name: .hotkeyRecording, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == UInt16(kVK_Escape) {
                self.stop()
            } else if let hk = Hotkey(event: e) {
                self.hotkey = hk
                self.stop()
                self.onChange?(hk)
            } else {
                NSSound.beep()
            }
            return nil
        }
        refreshTitle()
    }

    func stop() {
        guard let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
        refreshTitle()
        NotificationCenter.default.post(name: .hotkeyRecording, object: false)
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let folderLabel = NSTextField(labelWithString: "")
    private var recorders: [HotkeyRecorder] = []
    /// Moduser der registreringen feilet (kombinasjonen er opptatt).
    var failedModes: () -> Set<CaptureMode> = { [] }
    private var warningLabels: [CaptureMode: NSTextField] = [:]
    private let conflictBox = NSStackView()
    private let conflictLabel = NSTextField(wrappingLabelWithString: "")

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "screengrab – innstillinger"
        w.isReleasedWhenClosed = false
        self.init(window: w)
        w.delegate = self
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshWarnings),
                                               name: .hotkeysChanged, object: nil)
        // Systeminnstillinger kan ha blitt endret mens vinduet var i bakgrunnen.
        NotificationCenter.default.addObserver(self, selector: #selector(refreshWarnings),
                                               name: NSWindow.didBecomeKeyNotification, object: w)
    }

    private func build() {
        let s = Settings.shared
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderLabel.stringValue = s.folder.path
        folderLabel.toolTip = s.folder.path
        let choose = NSButton(title: "Velg…", target: self, action: #selector(chooseFolder))
        let folderRow = NSStackView(views: [folderLabel, choose])

        var rows: [[NSView]] = [[label("Mappe:"), folderRow]]
        for mode in CaptureMode.allCases {
            let rec = HotkeyRecorder(hotkey: s.hotkey(for: mode))
            rec.onChange = { s.setHotkey($0, for: mode) }
            recorders.append(rec)
            let off = NSButton(title: "Slå av", target: self, action: #selector(clearHotkey(_:)))
            off.tag = recorders.count - 1
            let std = NSButton(title: "Standard", target: self, action: #selector(resetHotkey(_:)))
            std.tag = recorders.count - 1
            let warn = NSTextField(labelWithString: "")
            warn.textColor = .systemRed
            warningLabels[mode] = warn
            rows.append([label(mode.title + ":"), NSStackView(views: [rec, off, std, warn])])
        }

        let savePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        savePopup.addItems(withTitles: SaveBehavior.allCases.map(\.title))
        savePopup.selectItem(at: SaveBehavior.allCases.firstIndex(of: s.saveBehavior) ?? 0)
        savePopup.target = self
        savePopup.action = #selector(saveBehaviorChanged(_:))
        let copyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        copyPopup.addItems(withTitles: CopyBehavior.allCases.map(\.title))
        copyPopup.selectItem(at: CopyBehavior.allCases.firstIndex(of: s.copyBehavior) ?? 0)
        copyPopup.target = self
        copyPopup.action = #selector(copyBehaviorChanged(_:))
        rows.append([label("Lagre-knappen (⌘S):"), savePopup])
        rows.append([label("Kopier-knappen (⌘C / ↩):"), copyPopup])

        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 12
        grid.columnSpacing = 10
        grid.row(at: 1 + CaptureMode.allCases.count).topPadding = 10

        // Advarsel når en hurtigtast også brukes av macOS (typisk ⌘⇧3).
        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                              accessibilityDescription: "Advarsel")!)
        icon.contentTintColor = .systemOrange
        conflictLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let open = NSButton(title: "Åpne Tastatur-innstillingene", target: self, action: #selector(openKeyboard))
        open.controlSize = .small
        let texts = NSStackView(views: [conflictLabel, open])
        texts.orientation = .vertical
        texts.alignment = .leading
        conflictBox.setViews([icon, texts], in: .leading)
        conflictBox.alignment = .top

        let note = NSTextField(wrappingLabelWithString:
            "Klikk på en hurtigtast og trykk den nye kombinasjonen (Esc avbryter). " +
            "⌘⇧3, ⌘⇧4 og ⌘⇧5 er macOS sine egne skjermbildetaster. Vil du bruke en av dem her, " +
            "må den tilsvarende snarveien slås av under Systeminnstillinger → Tastatur → Tastatursnarveier… → Skjermbilder.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [grid, conflictBox, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            note.widthAnchor.constraint(equalToConstant: 600),
            conflictLabel.widthAnchor.constraint(equalToConstant: 570),
        ])
        window?.contentView = content
        refreshWarnings()
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    @objc func refreshWarnings() {
        let failed = failedModes()
        let conflicts = Settings.shared.systemConflicts()
        for (mode, l) in warningLabels {
            if conflicts.contains(where: { $0.mode == mode }) {
                l.stringValue = "Brukes av macOS"
            } else {
                l.stringValue = failed.contains(mode) ? "Opptatt" : ""
            }
        }
        conflictBox.isHidden = conflicts.isEmpty
        conflictLabel.stringValue = conflicts.map {
            "\($0.hotkey.display) brukes også av macOS («\($0.name)»), så macOS tar et vanlig skjermbilde " +
            "i stedet for at screengrab reagerer. \(SystemShortcuts.howToDisable)"
        }.joined(separator: "\n")
    }

    @objc private func openKeyboard() { SystemShortcuts.openKeyboardSettings() }

    @objc private func saveBehaviorChanged(_ sender: NSPopUpButton) {
        Settings.shared.saveBehavior = SaveBehavior.allCases[sender.indexOfSelectedItem]
    }

    @objc private func copyBehaviorChanged(_ sender: NSPopUpButton) {
        Settings.shared.copyBehavior = CopyBehavior.allCases[sender.indexOfSelectedItem]
    }

    @objc private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = Settings.shared.folder
        p.prompt = "Bruk mappen"
        guard p.runModal() == .OK, let url = p.url else { return }
        Settings.shared.folder = url
        folderLabel.stringValue = url.path
        folderLabel.toolTip = url.path
    }

    @objc private func clearHotkey(_ sender: NSButton) {
        let mode = CaptureMode.allCases[sender.tag]
        recorders[sender.tag].hotkey = nil
        Settings.shared.setHotkey(nil, for: mode)
    }

    @objc private func resetHotkey(_ sender: NSButton) {
        let mode = CaptureMode.allCases[sender.tag]
        recorders[sender.tag].hotkey = mode.defaultHotkey
        Settings.shared.resetHotkey(for: mode)
    }

    func show() {
        refreshWarnings()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        recorders.forEach { $0.stop() }
    }
}
