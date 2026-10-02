import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var editors: [EditorWindowController] = []
    private var settingsWC: SettingsWindowController?
    private var failedModes: Set<CaptureMode> = []
    private var capturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "screengrab")
        img?.isTemplate = true
        statusItem.button?.image = img
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        registerHotkeys()
        NotificationCenter.default.addObserver(forName: .hotkeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotkeys()
        }
        // Mens en hurtigtast tas opp i innstillingene må de eksisterende være av,
        // ellers spiser Carbon tastetrykket før opptakeren ser det.
        NotificationCenter.default.addObserver(forName: .hotkeyRecording, object: nil, queue: .main) { [weak self] n in
            if (n.object as? Bool) == true { HotkeyCenter.shared.unregisterAll() } else { self?.registerHotkeys() }
        }

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.warnAboutSystemConflicts() }
    }

    /// Varsler ved oppstart hvis en hurtigtast (typisk ⌘⇧3) også er en påslått macOS-snarvei.
    /// Kan slås av med «Ikke vis igjen»; advarselen står uansett i menyen og innstillingene.
    private func warnAboutSystemConflicts() {
        let conflicts = Settings.shared.systemConflicts()
        guard !conflicts.isEmpty, !UserDefaults.standard.bool(forKey: "suppressSystemConflictWarning") else { return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.alertStyle = .warning
        let keys = conflicts.map(\.hotkey.display).joined(separator: ", ")
        a.messageText = "\(keys) brukes også av macOS"
        a.informativeText = conflicts.map { "\($0.hotkey.display) (\($0.mode.title)) kolliderer med macOS-snarveien «\($0.name)»." }
            .joined(separator: "\n") +
            "\n\nSå lenge macOS-snarveien er på, tar macOS et vanlig skjermbilde i stedet for at screengrab reagerer. " +
            SystemShortcuts.howToDisable
        a.addButton(withTitle: "Åpne Tastatur-innstillingene")
        a.addButton(withTitle: "OK")
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Ikke vis igjen"
        if a.runModal() == .alertFirstButtonReturn { SystemShortcuts.openKeyboardSettings() }
        if a.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: "suppressSystemConflictWarning")
        }
    }

    /// «Åpne med» fra Finder, eller `open -a screengrab bilde.png`.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { openEditor(url: $0, temporary: false) }
    }

    private func registerHotkeys() {
        HotkeyCenter.shared.unregisterAll()
        failedModes = []
        for mode in CaptureMode.allCases {
            guard let hk = Settings.shared.hotkey(for: mode) else { continue }
            let ok = HotkeyCenter.shared.register(id: mode.hotkeyID, hotkey: hk) { [weak self] in
                self?.capture(mode)
            }
            if !ok {
                failedModes.insert(mode)
                NSLog("screengrab: hurtigtast \(hk.display) for \(mode.rawValue) er opptatt")
            }
        }
        settingsWC?.refreshWarnings()
    }

    // MARK: Meny

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let conflicts = Settings.shared.systemConflicts()
        for mode in CaptureMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(captureFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            if let hk = Settings.shared.hotkey(for: mode) {
                if conflicts.contains(where: { $0.mode == mode }) {
                    item.title += "  (\(hk.display) brukes av macOS)"
                } else if failedModes.contains(mode) {
                    item.title += "  (\(hk.display) opptatt)"
                } else {
                    item.keyEquivalent = hk.menuKeyEquivalent
                    item.keyEquivalentModifierMask = hk.menuModifiers
                }
            }
            menu.addItem(item)
        }
        for c in conflicts {
            let fix = add(menu, "⚠︎ Slå av macOS-snarveien for \(c.hotkey.display)…", #selector(openKeyboardSettings))
            fix.toolTip = "«\(c.name)» bruker samme taster. \(SystemShortcuts.howToDisable)"
        }
        menu.addItem(.separator())
        let last = add(menu, "Tegn på siste skjermbilde", #selector(editLatest))
        last.isEnabled = Settings.shared.newestImage() != nil
        add(menu, "Åpne bilde for tegning…", #selector(openImage))
        add(menu, "Vis mappen i Finder", #selector(showFolder))
        menu.addItem(.separator())
        if !CGPreflightScreenCaptureAccess() {
            add(menu, "Gi tillatelse til skjermopptak…", #selector(openPrivacy))
        }
        add(menu, "Innstillinger…", #selector(showSettings), key: ",")
        add(menu, "Avslutt screengrab", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        // La menyen forsvinne før områdevalget starter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.capture(mode) }
    }

    @objc private func editLatest() {
        if let url = Settings.shared.newestImage() { openEditor(url: url, temporary: false) }
    }

    @objc private func openImage() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.directoryURL = Settings.shared.folder
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        openEditor(url: url, temporary: false)
    }

    @objc private func showFolder() {
        try? Settings.shared.ensureFolder()
        NSWorkspace.shared.open(Settings.shared.folder)
    }

    @objc private func openPrivacy() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openKeyboardSettings() { SystemShortcuts.openKeyboardSettings() }

    @objc private func showSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
            settingsWC?.failedModes = { [weak self] in self?.failedModes ?? [] }
        }
        settingsWC?.show()
    }

    // MARK: Opptak

    /// Bruker systemets eget områdevalg (screencapture -i): samme oppførsel som ⌘⇧4,
    /// inkludert mellomrom for å velge et helt vindu og Esc for å avbryte.
    func capture(_ mode: CaptureMode) {
        guard !capturing else { return }
        var args = ["-i"]
        var target: URL?
        switch mode {
        case .clipboard:
            args.append("-c")
        case .save:
            do { try Settings.shared.ensureFolder() } catch {
                alert("Fant ikke mappen", "\(Settings.shared.folder.path)\n\n\(error.localizedDescription)")
                return
            }
            target = Settings.shared.newScreenshotURL()
        case .edit:
            target = FileManager.default.temporaryDirectory.appendingPathComponent("screengrab-\(UUID().uuidString).png")
        }
        if let target { args.append(target.path) }

        capturing = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.capturing = false
                // Avbrutt med Esc → ingen fil.
                guard mode == .edit, let target, FileManager.default.fileExists(atPath: target.path) else { return }
                self.openEditor(url: target, temporary: true)
            }
        }
        do { try p.run() } catch {
            capturing = false
            alert("Kunne ikke starte screencapture", error.localizedDescription)
        }
    }

    private func openEditor(url: URL, temporary: Bool) {
        guard let wc = EditorWindowController(url: url, temporary: temporary) else {
            alert("Kunne ikke åpne bildet", url.path)
            return
        }
        wc.onClose = { [weak self, weak wc] in self?.editors.removeAll { $0 === wc } }
        editors.append(wc)
        wc.show()
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
