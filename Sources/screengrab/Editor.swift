import AppKit
import CoreImage
import ImageIO

// MARK: - Modell

enum Tool: Int, CaseIterable {
    case select, arrow, ellipse, rect, pen, marker, counter, redact, text

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .ellipse: return "circle"
        case .rect: return "rectangle"
        case .pen: return "scribble"
        case .marker: return "highlighter"
        case .counter: return "1.circle"
        case .redact: return "eye.slash"
        case .text: return "textformat"
        }
    }

    var shortcut: String {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .ellipse: return "o"
        case .rect: return "r"
        case .pen: return "p"
        case .marker: return "m"
        case .counter: return "n"
        case .redact: return "b"
        case .text: return "t"
        }
    }

    var help: String {
        switch self {
        case .select: return "Velg og flytt (V) – dra for å flytte, ⌫ sletter, piltaster finjusterer, dobbeltklikk endrer tekst"
        case .arrow: return "Pil (A)"
        case .ellipse: return "Sirkel/ellipse (O) – hold ⇧ for perfekt sirkel"
        case .rect: return "Rektangel (R) – hold ⇧ for kvadrat"
        case .pen: return "Frihånd (P)"
        case .marker: return "Markeringstusj (M)"
        case .counter: return "Nummererte markører (N) – hvert klikk gir neste nummer"
        case .redact: return "Skjul (B) – piksler, uskarp eller svart sladd. Svart sladd er sikrest."
        case .text: return "Tekst (T) – klikk for å skrive, klikk på en tekst for å endre den"
        }
    }
}

/// Et lite utvalg godt lesbare fonter.
enum TextFonts {
    static let all: [(family: String, title: String)] = [
        ("system", "SF Pro (system)"),
        ("Helvetica Neue", "Helvetica Neue"),
        ("Arial", "Arial"),
        ("Verdana", "Verdana"),
        ("Avenir Next", "Avenir Next"),
        ("Georgia", "Georgia"),
    ]
    static let sizes: [CGFloat] = [14, 18, 24, 32, 48]

    static func font(_ family: String, size: CGFloat, bold: Bool) -> NSFont {
        if family != "system",
           let f = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [],
                                             weight: bold ? 9 : 5, size: size) {
            return f
        }
        return .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    /// Kontrastkant rundt teksten, så den er lesbar på både lys og mørk bakgrunn.
    static func halo(for color: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return .white }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.6 ? NSColor.black.withAlphaComponent(0.85) : NSColor.white.withAlphaComponent(0.9)
    }
}

/// Hvordan et område skjules. Svart sladd fjerner innholdet helt; piksler og uskarphet
/// gjør det uleselig, men er i prinsippet mindre sikkert for svært kort tekst.
enum RedactMode: Int, CaseIterable {
    case pixelate, blur, solid

    var title: String {
        switch self {
        case .pixelate: return "Piksler"
        case .blur: return "Uskarp"
        case .solid: return "Sladd"
        }
    }
}

struct TextStyle {
    var family = "system"
    var size: CGFloat = 24
    var bold = true
}

/// Én tegnet figur, i bildets punktkoordinater (origo nede til venstre).
/// For tekst er points[0] tekstens øvre venstre hjørne.
struct Annotation {
    var tool: Tool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var style = TextStyle()
    var redact = RedactMode.pixelate
    var number = 0
    /// Ferdig behandlet utsnitt av originalbildet (piksler/uskarp) og området det dekker.
    var patch: CGImage?
    var patchRect: CGRect = .zero

    private var start: CGPoint { points.first ?? .zero }
    private var end: CGPoint { points.last ?? .zero }
    var box: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// For små til å beholde (et klikk uten å dra, eller tom tekst).
    var isTrivial: Bool {
        switch tool {
        case .pen, .marker: return points.count < 2
        case .text: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter: return false
        case .redact: return min(box.width, box.height) < 3
        default: return hypot(end.x - start.x, end.y - start.y) < 3
        }
    }

    func draw() {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }
        color.setStroke()
        color.setFill()
        switch tool {
        case .select:
            break
        case .arrow:
            drawArrow()
        case .ellipse:
            let p = NSBezierPath(ovalIn: box)
            p.lineWidth = width
            p.stroke()
        case .rect:
            let r = min(width, box.width / 2, box.height / 2)
            let p = NSBezierPath(roundedRect: box, xRadius: r, yRadius: r)
            p.lineWidth = width
            p.lineJoinStyle = .round
            p.stroke()
        case .pen:
            let p = smoothPath()
            p.lineWidth = width
            p.stroke()
        case .marker:
            // Multiply gjør at tekst under markeringen forblir lesbar.
            ctx.compositingOperation = .multiply
            color.withAlphaComponent(0.45).setStroke()
            let p = smoothPath()
            p.lineWidth = max(width * 4, 12)
            p.stroke()
        case .text:
            drawText(in: ctx)
        case .counter:
            drawCounter()
        case .redact:
            if redact == .solid || patch == nil {
                NSColor.black.setFill()
                NSBezierPath(rect: redact == .solid ? box : patchRect).fill()
            } else if let patch {
                // Pikslene er lagret i lav oppløsning; uten interpolasjon blir de skarpe blokker.
                ctx.imageInterpolation = redact == .pixelate ? .none : .high
                ctx.cgContext.draw(patch, in: patchRect)
            }
        }
    }

    // MARK: Velg og flytt

    private var strokeWidth: CGFloat { tool == .marker ? max(width * 4, 12) : width }
    private var arrowHead: CGFloat { max(width * 4.5, 14) }

    /// Linjen eller omrisset figuren tegnes langs (for treff på strek).
    private var outline: CGPath? {
        switch tool {
        case .arrow:
            let p = CGMutablePath()
            p.move(to: start)
            p.addLine(to: end)
            return p
        case .ellipse: return CGPath(ellipseIn: box, transform: nil)
        case .rect: return CGPath(rect: box, transform: nil)
        case .pen, .marker: return smoothPath().cgPath
        default: return nil
        }
    }

    /// Treffer punktet figuren? Ellipser og rektangler treffes på streken, så det som ligger inni kan velges.
    func hitTest(_ p: CGPoint, tolerance t: CGFloat) -> Bool {
        switch tool {
        case .select: return false
        case .counter: return hypot(p.x - start.x, p.y - start.y) <= counterDiameter / 2 + t
        case .redact: return box.insetBy(dx: -t, dy: -t).contains(p)
        case .text: return textRect.insetBy(dx: -t, dy: -t).contains(p)
        case .arrow where hypot(p.x - end.x, p.y - end.y) <= arrowHead + t:
            return true
        default:
            guard let path = outline else { return false }
            return path.copy(strokingWithWidth: strokeWidth + 2 * t, lineCap: .round, lineJoin: .round, miterLimit: 10)
                .contains(p)
        }
    }

    /// Området figuren dekker (for markeringsrammen).
    var bounds: CGRect {
        switch tool {
        case .select: return .zero
        case .counter:
            let d = counterDiameter
            return CGRect(x: start.x - d / 2, y: start.y - d / 2, width: d, height: d)
        case .redact: return box
        case .text: return textRect
        case .arrow: return box.insetBy(dx: -arrowHead / 2, dy: -arrowHead / 2)
        default:
            return (outline?.boundingBoxOfPath ?? box).insetBy(dx: -strokeWidth / 2, dy: -strokeWidth / 2)
        }
    }

    // MARK: Endre størrelse

    enum Handle: Equatable {
        case end(Int)  // pilens start (0) eller spiss (1)
        case box(Int)  // 0–7 rundt rammen, mot klokka fra nede til venstre
    }

    /// Rammen håndtakene sitter på.
    var frame: CGRect {
        switch tool {
        case .pen, .marker:
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        case .text: return textRect
        case .counter:
            let d = counterDiameter
            return CGRect(x: start.x - d / 2, y: start.y - d / 2, width: d, height: d)
        default: return box
        }
    }

    static func boxHandlePoints(_ f: CGRect) -> [CGPoint] {
        [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
         CGPoint(x: f.maxX, y: f.midY), CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.midX, y: f.maxY),
         CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.minX, y: f.midY)]
    }

    /// Håndtakene for en valgt figur. Tekst og markører skaleres jevnt og har bare hjørner.
    var handles: [(handle: Handle, point: CGPoint)] {
        switch tool {
        case .select: return []
        case .arrow: return [(.end(0), start), (.end(1), end)]
        default:
            let all = Annotation.boxHandlePoints(frame)
            let idx = (tool == .text || tool == .counter) ? [0, 2, 4, 6] : Array(0..<8)
            return idx.map { (.box($0), all[$0]) }
        }
    }

    /// Figuren med håndtaket dratt til p (beregnes alltid fra originalen da draget startet).
    func resized(_ h: Handle, to p: CGPoint) -> Annotation {
        var a = self
        switch h {
        case .end(let i):
            a.points[i == 0 ? 0 : a.points.count - 1] = p
            return a
        case .box(let i):
            let b = frame
            var x0 = b.minX, x1 = b.maxX, y0 = b.minY, y1 = b.maxY
            if [0, 6, 7].contains(i) { x0 = p.x }
            if [2, 3, 4].contains(i) { x1 = p.x }
            if [0, 1, 2].contains(i) { y0 = p.y }
            if [4, 5, 6].contains(i) { y1 = p.y }
            let nb = CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
            // Hjørnet rett overfor det som dras, står fast for tekst og markører.
            let fixed = Annotation.boxHandlePoints(b)[(i + 4) % 8]
            switch tool {
            case .pen, .marker:
                let sx = b.width > 0.5 ? nb.width / b.width : 1
                let sy = b.height > 0.5 ? nb.height / b.height : 1
                a.points = points.map { CGPoint(x: nb.minX + ($0.x - b.minX) * sx, y: nb.minY + ($0.y - b.minY) * sy) }
            case .counter:
                let d = min(max((nb.width + nb.height) / 2, 18), 240)
                a.width = (d - 16) / 3.8
                let dx: CGFloat = p.x >= fixed.x ? 1 : -1, dy: CGFloat = p.y >= fixed.y ? 1 : -1
                a.points = [CGPoint(x: fixed.x + dx * d / 2, y: fixed.y + dy * d / 2)]
            case .text:
                let rw = b.width > 0 ? nb.width / b.width : 1, rh = b.height > 0 ? nb.height / b.height : 1
                a.style.size = min(max(style.size * (rw + rh) / 2, 8), 300)
                let size = a.textRect.size
                let left = (i == 2 || i == 4) ? fixed.x : fixed.x - size.width
                let top = (i == 0 || i == 2) ? fixed.y : fixed.y + size.height
                a.points = [CGPoint(x: left, y: top)]
            default:
                a.points = [CGPoint(x: nb.minX, y: nb.minY), CGPoint(x: nb.maxX, y: nb.maxY)]
            }
            return a
        }
    }

    func translated(dx: CGFloat, dy: CGFloat) -> Annotation {
        var a = self
        a.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        a.patchRect = patchRect.offsetBy(dx: dx, dy: dy)
        return a
    }

    // MARK: Tekst

    var font: NSFont { TextFonts.font(style.family, size: style.size, bold: style.bold) }

    private func attributed(_ extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for (k, v) in extra { attrs[k] = v }
        return NSAttributedString(string: text, attributes: attrs)
    }

    var textRect: CGRect {
        let s = attributed().boundingRect(with: CGSize(width: 100_000, height: 100_000),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        return CGRect(x: start.x, y: start.y - ceil(s.height), width: ceil(s.width), height: ceil(s.height))
    }

    private func drawText(in ctx: NSGraphicsContext) {
        let r = textRect
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        ctx.cgContext.setLineJoin(.round)
        // Først en bred kontur i kontrastfarge (positiv strokeWidth = bare kontur), så selve teksten oppå.
        let halo = TextFonts.halo(for: color)
        attributed([.strokeColor: halo, .strokeWidth: 16, .foregroundColor: halo]).draw(with: r, options: opts)
        attributed().draw(with: r, options: opts)
    }

    // MARK: Nummererte markører

    /// Diameter etter valgt tykkelse (tynn/middels/tykk → 24/32/42 pt).
    var counterDiameter: CGFloat { 16 + width * 3.8 }

    private func drawCounter() {
        let d = counterDiameter
        let circle = CGRect(x: start.x - d / 2, y: start.y - d / 2, width: d, height: d)
        // Kontrastkant skiller markøren fra bakgrunnen (hvit rundt mørke farger, mørk rundt lyse).
        TextFonts.halo(for: color).setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: -max(2, d * 0.08), dy: -max(2, d * 0.08))).fill()
        color.setFill()
        NSBezierPath(ovalIn: circle).fill()

        let label = "\(number)" as NSString
        let size = d * (label.length > 1 ? 0.48 : 0.58)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: TextFonts.halo(for: color).withAlphaComponent(1),
        ]
        let t = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: start.x - t.width / 2, y: start.y - t.height / 2), withAttributes: attrs)
    }

    // MARK: Figurer

    private func drawArrow() {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = hypot(dx, dy)
        guard len > 0.5 else { return }
        let angle = atan2(dy, dx)
        let head = min(max(width * 4.5, 14), len * 0.6)
        let spread: CGFloat = .pi / 7
        let left = CGPoint(x: end.x - head * cos(angle - spread), y: end.y - head * sin(angle - spread))
        let right = CGPoint(x: end.x - head * cos(angle + spread), y: end.y - head * sin(angle + spread))
        // Skaftet slutter inne i pilhodet så den runde enden ikke stikker ut av spissen.
        let back = head * cos(spread) * 0.8
        let shaftEnd = CGPoint(x: end.x - back * cos(angle), y: end.y - back * sin(angle))

        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        shaft.stroke()

        let tip = NSBezierPath()
        tip.move(to: end)
        tip.line(to: left)
        tip.line(to: right)
        tip.close()
        tip.lineJoinStyle = .round
        tip.lineWidth = max(1, width / 3)
        tip.fill()
        tip.stroke()
    }

    private func smoothPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        guard let first = points.first else { return p }
        p.move(to: first)
        if points.count < 3 {
            points.dropFirst().forEach { p.line(to: $0) }
            return p
        }
        // Kvadratisk utjevning gjennom midtpunktene.
        for i in 1..<points.count - 1 {
            let a = points[i], b = points[i + 1]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            p.curve(to: mid, controlPoint1: a, controlPoint2: a)
        }
        p.line(to: points[points.count - 1])
        return p
    }
}

final class EditorDocument {
    let url: URL
    let cgImage: CGImage
    /// Størrelse i punkter (Retina-skjermbilder har 2 piksler per punkt).
    let size: CGSize
    let image: NSImage
    private(set) var annotations: [Annotation] = []
    // Angre/gjør om lagrer hele lista; den er liten, og da dekkes også endring og sletting av tekst.
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.url = url
        cgImage = cg
        var size = CGSize(width: cg.width, height: cg.height)
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let dpi = props[kCGImagePropertyDPIWidth] as? CGFloat, dpi > 72 {
            size = CGSize(width: CGFloat(cg.width) * 72 / dpi, height: CGFloat(cg.height) * 72 / dpi)
        }
        self.size = size
        image = NSImage(cgImage: cg, size: size)
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Lager utsnittet som dekker et område med piksler eller uskarphet, fra originalbildet.
    func applyRedaction(to a: inout Annotation) {
        a.patch = nil
        a.patchRect = a.box.intersection(CGRect(origin: .zero, size: size))
        guard a.redact != .solid, a.patchRect.width >= 1, a.patchRect.height >= 1 else { return }
        let r = a.patchRect
        let sx = CGFloat(cgImage.width) / size.width
        // CGImage-utsnitt har origo øverst til venstre.
        let px = CGRect(x: r.minX * sx, y: (size.height - r.maxY) * sx, width: r.width * sx, height: r.height * sx).integral
        guard let crop = cgImage.cropping(to: px) else { return }
        a.patchRect = CGRect(x: px.minX / sx, y: size.height - px.maxY / sx, width: px.width / sx, height: px.height / sx)
        switch a.redact {
        case .pixelate:
            let block = 12 * sx // ca. 12 pt store blokker
            let w = max(1, Int((CGFloat(crop.width) / block).rounded()))
            let h = max(1, Int((CGFloat(crop.height) / block).rounded()))
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .high
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            a.patch = ctx.makeImage()
        case .blur:
            let ci = CIImage(cgImage: crop)
            let out = ci.clampedToExtent().applyingGaussianBlur(sigma: 10 * sx).cropped(to: ci.extent)
            a.patch = Self.ciContext.createCGImage(out, from: ci.extent)
        case .solid:
            break
        }
    }

    /// Neste nummer: ett høyere enn det høyeste i bildet (så angre holder rekkefølgen).
    var nextCounterNumber: Int {
        (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var isEmpty: Bool { annotations.isEmpty }

    func mutate(_ change: (inout [Annotation]) -> Void) {
        undoStack.append(annotations)
        change(&annotations)
        redoStack.removeAll()
    }

    func add(_ a: Annotation) { mutate { $0.append(a) } }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    /// Bildet med figurene, i full oppløsning og originalens fargerom.
    func renderPNG() -> Data? {
        let w = cgImage.width, h = cgImage.height
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cgImage.colorSpace ?? srgb, bitmapInfo: info)
                ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                             space: srgb, bitmapInfo: info) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(w) / size.width, y: CGFloat(h) / size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        annotations.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        guard let out = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = size // gir 144 dpi i PNG-en, slik at Retina-bilder limes inn i riktig størrelse
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Tegneflate

final class CanvasView: NSView, NSTextFieldDelegate {
    let doc: EditorDocument
    var tool: Tool = .arrow {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var color: NSColor = .systemRed {
        didSet { pendingText?.color = color; styleTextField() }
    }
    var lineWidth: CGFloat = 4
    var redactMode = RedactMode.pixelate
    var textStyle = TextStyle() {
        didSet { pendingText?.style = textStyle; styleTextField() }
    }
    var onCommit: (() -> Void)?
    private var current: Annotation?

    // Velg og flytt: valgt figur (indeks i doc.annotations) og kopien som flyttes mens musen dras.
    var selection: Int? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private var moveStart: CGPoint?
    private var moving: Annotation?
    // Endre størrelse: håndtaket som dras og figuren slik den var da draget startet.
    private var resizeHandle: Annotation.Handle?
    private var resizeOriginal: Annotation?
    private var didResize = false
    private let handleSize: CGFloat = 8

    // Tekst som skrives akkurat nå: et tekstfelt oppå bildet til teksten er ferdig.
    private var textField: NSTextField?
    private var pendingText: Annotation?
    private var editingIndex: Int?
    var isEditingText: Bool { textField != nil }

    init(doc: EditorDocument) {
        self.doc = doc
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Bildet tilpasset vinduet, aldri forstørret.
    private var imageRect: CGRect {
        let s = min(bounds.width / doc.size.width, bounds.height / doc.size.height, 1)
        let w = doc.size.width * s, h = doc.size.height * s
        return CGRect(x: ((bounds.width - w) / 2).rounded(), y: ((bounds.height - h) / 2).rounded(), width: w, height: h)
    }

    private var scale: CGFloat { imageRect.width / doc.size.width }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: (p.x - r.minX) / scale, y: (p.y - r.minY) / scale)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: r.minX + p.x * scale, y: r.minY + p.y * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        let r = imageRect
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        let t = NSAffineTransform()
        t.translateX(by: r.minX, yBy: r.minY)
        t.scale(by: scale)
        t.concat()
        doc.image.draw(in: CGRect(origin: .zero, size: doc.size))
        for (i, a) in doc.annotations.enumerated() where i != editingIndex && !(i == selection && moving != nil) {
            a.draw()
        }
        moving?.draw()
        current?.draw()
        ctx.restoreGraphicsState()
        drawSelection()
    }

    private func drawSelection() {
        guard let sel = selection, sel < doc.annotations.count else { return }
        let b = (moving ?? doc.annotations[sel]).bounds
        let o = toView(b.origin)
        let r = CGRect(x: o.x, y: o.y, width: b.width * scale, height: b.height * scale).insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        path.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
        path.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        for h in (moving ?? doc.annotations[sel]).handles {
            let v = toView(h.point)
            let r = CGRect(x: v.x - handleSize / 2, y: v.y - handleSize / 2, width: handleSize, height: handleSize)
            let knob: NSBezierPath
            if case .end = h.handle { knob = NSBezierPath(ovalIn: r.insetBy(dx: -1, dy: -1)) } else { knob = NSBezierPath(rect: r) }
            NSColor.white.setFill()
            knob.fill()
            knob.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
            knob.stroke()
        }
    }

    private func handle(at viewPoint: CGPoint) -> Annotation.Handle? {
        guard let sel = selection, sel < doc.annotations.count else { return nil }
        let reach = handleSize / 2 + 3
        return doc.annotations[sel].handles.last { h in
            let v = toView(h.point)
            return abs(v.x - viewPoint.x) <= reach && abs(v.y - viewPoint.y) <= reach
        }?.handle
    }

    override func resetCursorRects() {
        let cursor: NSCursor = tool == .text ? .iBeam : tool == .select ? .arrow : .crosshair
        addCursorRect(imageRect, cursor: cursor)
        guard tool == .select, let sel = selection, sel < doc.annotations.count else { return }
        for h in doc.annotations[sel].handles {
            let v = toView(h.point)
            let c: NSCursor
            switch h.handle {
            case .box(1), .box(5): c = .resizeUpDown
            case .box(3), .box(7): c = .resizeLeftRight
            default: c = .crosshair
            }
            addCursorRect(CGRect(x: v.x - 7, y: v.y - 7, width: 14, height: 14), cursor: c)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if isEditingText { styleTextField() }
    }

    override func mouseDown(with event: NSEvent) {
        // Et klikk utenfor tekstfeltet avslutter teksten som skrives.
        if isEditingText {
            commitText()
            return
        }
        window?.makeFirstResponder(self)
        let p = toImage(convert(event.locationInWindow, from: nil))
        if tool == .select {
            if let h = handle(at: convert(event.locationInWindow, from: nil)), let sel = selection {
                resizeHandle = h
                resizeOriginal = doc.annotations[sel]
                moving = resizeOriginal
                didResize = false
                return
            }
            let hit = doc.annotations.lastIndex { $0.hitTest(p, tolerance: 6 / scale) }
            selection = hit
            guard let hit else { return }
            if event.clickCount == 2, doc.annotations[hit].tool == .text {
                selection = nil
                beginText(at: p, existing: hit)
                return
            }
            moveStart = p
            moving = doc.annotations[hit]
            return
        }
        if tool == .text {
            let hit = doc.annotations.lastIndex { $0.tool == .text && $0.textRect.insetBy(dx: -6, dy: -6).contains(p) }
            beginText(at: p, existing: hit)
            return
        }
        current = Annotation(tool: tool, points: [p, p], color: color, width: lineWidth, redact: redactMode)
        if tool == .pen || tool == .marker { current?.points = [p] }
        if tool == .counter {
            current?.points = [p]
            current?.number = doc.nextCounterNumber
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var p = toImage(convert(event.locationInWindow, from: nil))
        if let h = resizeHandle, let orig = resizeOriginal {
            var m = orig.resized(h, to: p)
            if m.tool == .redact { doc.applyRedaction(to: &m) }
            moving = m
            didResize = true
            needsDisplay = true
            return
        }
        if let start = moveStart, let sel = selection {
            var m = doc.annotations[sel].translated(dx: p.x - start.x, dy: p.y - start.y)
            if m.tool == .redact { doc.applyRedaction(to: &m) }
            moving = m
            needsDisplay = true
            return
        }
        guard var a = current else { return }
        switch a.tool {
        case .pen, .marker:
            if let last = a.points.last, hypot(p.x - last.x, p.y - last.y) < 1.5 { return }
            a.points.append(p)
        case .counter:
            a.points[0] = p
        default:
            if event.modifierFlags.contains(.shift) { p = constrain(from: a.points[0], to: p, tool: a.tool) }
            a.points[1] = p
            if a.tool == .redact { doc.applyRedaction(to: &a) }
        }
        current = a
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if resizeHandle != nil {
            if didResize, let sel = selection, let m = moving {
                doc.mutate { $0[sel] = m }
                onCommit?()
            }
            resizeHandle = nil
            resizeOriginal = nil
            moving = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
        if moveStart != nil {
            let p = toImage(convert(event.locationInWindow, from: nil))
            if let start = moveStart, let sel = selection, let m = moving, hypot(p.x - start.x, p.y - start.y) > 0.5 {
                doc.mutate { $0[sel] = m }
                onCommit?()
            }
            moveStart = nil
            moving = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
        if let a = current, !a.isTrivial {
            doc.add(a)
            onCommit?()
        }
        current = nil
        needsDisplay = true
    }

    func cancelDrawing() {
        current = nil
        moveStart = nil
        moving = nil
        resizeHandle = nil
        resizeOriginal = nil
        selection = nil
        needsDisplay = true
    }

    func deleteSelection() {
        guard let sel = selection, sel < doc.annotations.count else { return NSSound.beep() }
        selection = nil
        doc.mutate { $0.remove(at: sel) }
        onCommit?()
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let sel = selection, sel < doc.annotations.count else { return }
        var m = doc.annotations[sel].translated(dx: dx, dy: dy)
        if m.tool == .redact { doc.applyRedaction(to: &m) }
        doc.mutate { $0[sel] = m }
        onCommit?()
        window?.invalidateCursorRects(for: self)
    }

    /// Ny farge på valgt figur (sladd/piksler har ingen farge).
    func recolorSelection(_ color: NSColor) {
        guard let sel = selection, sel < doc.annotations.count,
              doc.annotations[sel].tool != .redact, doc.annotations[sel].color != color else { return }
        doc.mutate { $0[sel].color = color }
        onCommit?()
    }

    /// ⇧: kvadrat/sirkel, eller pil i 45°-trinn.
    private func constrain(from s: CGPoint, to p: CGPoint, tool: Tool) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        if tool == .arrow {
            let step = CGFloat.pi / 4
            let a = (atan2(dy, dx) / step).rounded() * step
            let len = hypot(dx, dy)
            return CGPoint(x: s.x + len * cos(a), y: s.y + len * sin(a))
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: s.x + (dx < 0 ? -side : side), y: s.y + (dy < 0 ? -side : side))
    }

    // MARK: Tekst

    private func beginText(at p: CGPoint, existing index: Int?) {
        let a: Annotation
        if let index {
            a = doc.annotations[index]
            editingIndex = index
        } else {
            // Teksten plasseres slik at klikkpunktet havner midt i første linje.
            let lineHeight = TextFonts.font(textStyle.family, size: textStyle.size, bold: textStyle.bold).boundingRectForFont.height
            a = Annotation(tool: .text, points: [CGPoint(x: p.x, y: p.y + lineHeight / 2)],
                           color: color, width: lineWidth, style: textStyle)
        }
        pendingText = a
        let f = NSTextField(string: a.text)
        f.isBezeled = false
        f.isBordered = false
        f.drawsBackground = true
        f.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35)
        f.focusRingType = .none
        f.usesSingleLineMode = false
        f.cell?.wraps = false
        f.cell?.isScrollable = false
        f.delegate = self
        addSubview(f)
        textField = f
        styleTextField()
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectedRange = NSRange(location: (a.text as NSString).length, length: 0)
        needsDisplay = true
    }

    private func styleTextField() {
        guard let f = textField, let a = pendingText else { return }
        f.font = TextFonts.font(a.style.family, size: a.style.size * scale, bold: a.style.bold)
        f.textColor = a.color
        resizeTextField()
    }

    private func resizeTextField() {
        guard let f = textField, let a = pendingText, let font = f.font else { return }
        var text = f.currentEditor()?.string ?? f.stringValue
        if text.isEmpty || text.hasSuffix("\n") { text += " " }
        let size = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: CGSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let top = toView(a.points[0])
        // Tekstfeltet har ca. 2 pt innvendig marg til venstre.
        f.frame = NSRect(x: top.x - 2, y: top.y - ceil(size.height), width: ceil(size.width) + 16, height: ceil(size.height))
    }

    func controlTextDidChange(_ obj: Notification) { resizeTextField() }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    /// ↩ avslutter teksten, ⇧↩ / ⌥↩ gir ny linje, Esc forkaster.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let f = NSApp.currentEvent?.modifierFlags ?? []
            if f.contains(.shift) || f.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                resizeTextField()
            } else {
                commitText()
            }
            return true
        }
        if sel == #selector(NSResponder.insertLineBreak(_:)) || sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            resizeTextField()
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            endTextEditing(keep: false)
            return true
        }
        return false
    }

    /// Kalles også før kopiering, lagring og verktøybytte.
    func commitText() { endTextEditing(keep: true) }

    private func endTextEditing(keep: Bool) {
        guard let f = textField, var a = pendingText else { return }
        a.text = f.currentEditor()?.string ?? f.stringValue
        let index = editingIndex
        textField = nil
        pendingText = nil
        editingIndex = nil
        f.delegate = nil
        window?.makeFirstResponder(self)
        f.removeFromSuperview()
        if keep {
            if let index {
                doc.mutate { list in
                    if a.isTrivial { list.remove(at: index) } else { list[index] = a }
                }
            } else if !a.isTrivial {
                doc.add(a)
            }
            onCommit?()
        }
        needsDisplay = true
    }
}

// MARK: - Fargeknapp

final class SwatchButton: NSButton {
    let swatch: NSColor
    var selected = false { didSet { needsDisplay = true } }

    init(color: NSColor, target: AnyObject, action: Selector) {
        swatch = color
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        title = ""
        self.target = target
        self.action = action
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        swatch.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(ovalIn: r).stroke()
        if selected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

// MARK: - Vindu

/// Håndterer tastatursnarveier selv, siden appen ikke har noen menylinje.
final class EditorWindow: NSWindow {
    weak var editor: EditorWindowController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let ed = editor else { return super.performKeyEquivalent(with: event) }
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let c = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if ed.canvas.isEditingText {
            // ↩ skal avslutte teksten, ikke trykke standardknappen (Kopier).
            if event.keyCode == 36 || event.keyCode == 76 { return false }
            // Uten menylinje må vanlig tekstredigering sendes videre for hånd.
            if f.contains(.command), !f.contains(.shift) {
                let edit: [String: Selector] = ["c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
                                                "x": #selector(NSText.cut(_:)), "a": #selector(NSText.selectAll(_:))]
                if let sel = edit[c] { return NSApp.sendAction(sel, to: nil, from: self) }
                if c == "z" { (firstResponder as? NSTextView)?.undoManager?.undo(); return true }
            }
        }

        guard f.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let shift = f.contains(.shift)
        switch c {
        case "c": ed.copyClicked()
        case "s": shift ? ed.saveAsClicked() : ed.saveClicked()
        case "z": shift ? ed.redo() : ed.undo()
        case "w": performClose(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.isDisjoint(with: [.command, .control, .option]), let ed = editor,
              let c = event.charactersIgnoringModifiers?.lowercased() else { return super.keyDown(with: event) }
        if event.keyCode == 53 { ed.canvas.cancelDrawing(); return } // Esc
        if event.keyCode == 51 || event.keyCode == 117 { ed.canvas.deleteSelection(); return } // ⌫ / Delete
        let step: CGFloat = f.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: ed.canvas.nudgeSelection(dx: -step, dy: 0); return
        case 124: ed.canvas.nudgeSelection(dx: step, dy: 0); return
        case 125: ed.canvas.nudgeSelection(dx: 0, dy: -step); return
        case 126: ed.canvas.nudgeSelection(dx: 0, dy: step); return
        default: break
        }
        if let tool = Tool.allCases.first(where: { $0.shortcut == c }) { ed.select(tool: tool); return }
        if let n = Int(c), n >= 1, n <= EditorWindowController.palette.count { ed.select(colorIndex: n - 1); return }
        super.keyDown(with: event)
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    static let palette: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1), // rød
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1), // oransje
        NSColor(srgbRed: 1.00, green: 0.84, blue: 0.00, alpha: 1), // gul
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1), // grønn
        NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1), // blå
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1), // lilla
        .black,
        .white,
    ]
    static let widths: [CGFloat] = [2, 4, 7]

    let doc: EditorDocument
    let canvas: CanvasView
    private let temporary: Bool
    private var savedURL: URL?
    var onClose: (() -> Void)?

    private let bar = NSStackView()
    private let toolControl = NSSegmentedControl()
    private let widthControl = NSSegmentedControl()
    private let redactControl = NSSegmentedControl()
    private var swatches: [SwatchButton] = []
    private let colorWell = NSColorWell(style: .minimal)
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let boldButton = NSButton()
    private let textControls = NSStackView()
    private let undoButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private var copyButton: NSButton!
    private var saveButton: NSButton!

    // Husk valgene mellom vinduer.
    private static var lastTool: Tool = .arrow
    private static var lastColor: NSColor = palette[0]
    private static var lastWidth = 1
    private static var lastTextStyle = TextStyle()
    private static var lastRedact = RedactMode.pixelate

    init?(url: URL, temporary: Bool) {
        guard let doc = EditorDocument(url: url) else { return nil }
        self.doc = doc
        self.temporary = temporary
        canvas = CanvasView(doc: doc)

        let window = EditorWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
        window.title = temporary ? "Nytt skjermbilde" : url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.editor = self
        window.delegate = self
        buildUI()
        apply(color: Self.lastColor)
        widthControl.selectedSegment = Self.lastWidth
        canvas.lineWidth = Self.widths[Self.lastWidth]
        applyTextStyleToControls(Self.lastTextStyle)
        canvas.textStyle = Self.lastTextStyle
        redactControl.selectedSegment = Self.lastRedact.rawValue
        canvas.redactMode = Self.lastRedact
        select(tool: Self.lastTool)
        canvas.onCommit = { [weak self] in self?.refresh() }
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(updateButtonTitles),
                                               name: .behaviorChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let window else { return }

        toolControl.segmentStyle = .separated
        toolControl.trackingMode = .selectOne
        toolControl.segmentCount = Tool.allCases.count
        for t in Tool.allCases {
            toolControl.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.help), forSegment: t.rawValue)
            toolControl.setToolTip(t.help, forSegment: t.rawValue)
            toolControl.setWidth(34, forSegment: t.rawValue)
        }
        toolControl.target = self
        toolControl.action = #selector(toolChanged)

        swatches = Self.palette.enumerated().map { i, c in
            let b = SwatchButton(color: c, target: self, action: #selector(swatchClicked(_:)))
            b.tag = i
            b.toolTip = "Farge (\(i + 1))"
            return b
        }
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged)
        colorWell.toolTip = "Valgfri farge"
        colorWell.widthAnchor.constraint(equalToConstant: 30).isActive = true

        widthControl.segmentStyle = .separated
        widthControl.trackingMode = .selectOne
        widthControl.segmentCount = Self.widths.count
        for (i, w) in Self.widths.enumerated() {
            widthControl.setImage(lineImage(width: w), forSegment: i)
            widthControl.setWidth(30, forSegment: i)
        }
        widthControl.setToolTip("Tynn", forSegment: 0)
        widthControl.setToolTip("Middels", forSegment: 1)
        widthControl.setToolTip("Tykk", forSegment: 2)
        widthControl.target = self
        widthControl.action = #selector(widthChanged)

        // Skjulemåte (vises bare med skjul-verktøyet).
        redactControl.segmentStyle = .separated
        redactControl.trackingMode = .selectOne
        redactControl.segmentCount = RedactMode.allCases.count
        for m in RedactMode.allCases { redactControl.setLabel(m.title, forSegment: m.rawValue) }
        redactControl.setToolTip("Gjør området om til store piksler", forSegment: RedactMode.pixelate.rawValue)
        redactControl.setToolTip("Gjør området uskarpt", forSegment: RedactMode.blur.rawValue)
        redactControl.setToolTip("Dekk området med svart (sikrest)", forSegment: RedactMode.solid.rawValue)
        redactControl.target = self
        redactControl.action = #selector(redactChanged)

        // Tekstvalg (vises bare med tekstverktøyet).
        for f in TextFonts.all {
            fontPopup.addItem(withTitle: f.title)
            fontPopup.lastItem?.attributedTitle = NSAttributedString(
                string: f.title, attributes: [.font: TextFonts.font(f.family, size: 13, bold: false)])
        }
        fontPopup.toolTip = "Font"
        fontPopup.target = self
        fontPopup.action = #selector(textStyleChanged)
        sizePopup.addItems(withTitles: TextFonts.sizes.map { "\(Int($0)) pt" })
        sizePopup.toolTip = "Tekststørrelse"
        sizePopup.target = self
        sizePopup.action = #selector(textStyleChanged)
        boldButton.setButtonType(.pushOnPushOff)
        boldButton.bezelStyle = .rounded
        boldButton.image = NSImage(systemSymbolName: "bold", accessibilityDescription: "Fet")
        boldButton.title = ""
        boldButton.toolTip = "Fet skrift"
        boldButton.target = self
        boldButton.action = #selector(textStyleChanged)
        textControls.setViews([fontPopup, sizePopup, boldButton], in: .leading)
        textControls.spacing = 6

        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Angre")
        undoButton.bezelStyle = .rounded
        undoButton.toolTip = "Angre (⌘Z), gjør om (⌘⇧Z)"
        undoButton.target = self
        undoButton.action = #selector(undoClicked)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        copyButton = button("Kopier", "doc.on.doc", #selector(copyClicked))
        copyButton.keyEquivalent = "\r" // standardknapp, blå
        saveButton = button("Lagre", "square.and.arrow.down", #selector(saveClicked))
        let saveAs = button("Lagre som…", nil, #selector(saveAsClicked))
        saveAs.toolTip = "Lagre et annet sted (⌘⇧S)"
        updateButtonTitles()

        // Øverst: verktøy for å tegne. Nederst: status og knapper for å bli ferdig,
        // med hovedknappen (↩) nederst til høyre som i macOS-dialoger.
        let colors = NSStackView(views: swatches + [colorWell])
        colors.spacing = 2
        // Fleksibelt mellomrom til slutt, så verktøyene holder seg samlet til venstre.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        bar.setViews([toolControl, colors, widthControl, redactControl, textControls, undoButton, spacer], in: .leading)
        bar.spacing = 12
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        let actions = NSStackView()
        actions.setViews([statusLabel], in: .leading)
        actions.setViews([saveAs, saveButton, copyButton], in: .trailing)
        actions.spacing = 8
        actions.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)

        let topLine = NSBox(), bottomLine = NSBox()
        topLine.boxType = .separator
        bottomLine.boxType = .separator

        let content = NSView()
        for v in [bar, topLine, canvas, bottomLine, actions] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
            v.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
            v.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            topLine.topAnchor.constraint(equalTo: bar.bottomAnchor),
            canvas.topAnchor.constraint(equalTo: topLine.bottomAnchor),
            bottomLine.topAnchor.constraint(equalTo: canvas.bottomAnchor),
            actions.topAnchor.constraint(equalTo: bottomLine.bottomAnchor),
            actions.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content

        // Start i bildets faktiske størrelse, men aldri større enn ~85 % av skjermen.
        // Verktøylinjen er bredest når tekstvalgene vises.
        textControls.isHidden = false
        widthControl.isHidden = true
        redactControl.isHidden = true
        let barSize = bar.fittingSize, actionsSize = actions.fittingSize
        let chrome = barSize.height + actionsSize.height + 2
        let minWidth = max(barSize.width, actionsSize.width)
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let maxW = screen.width * 0.85, maxH = screen.height * 0.85 - chrome
        let s = min(1, maxW / doc.size.width, maxH / doc.size.height)
        let size = NSSize(width: max(doc.size.width * s, minWidth),
                          height: max(doc.size.height * s, 160) + chrome)
        window.contentMinSize = NSSize(width: minWidth, height: chrome + 120)
        window.setContentSize(size)
        window.center()
    }

    private func button(_ title: String, _ symbol: String?, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        if let symbol {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            b.imagePosition = .imageLeading
        }
        return b
    }

    @objc private func updateButtonTitles() {
        let copy = Settings.shared.copyBehavior, save = Settings.shared.saveBehavior
        copyButton.title = copy.buttonTitle
        copyButton.toolTip = "\(copy.title) (⌘C eller ↩)"
        saveButton.title = save.buttonTitle
        saveButton.toolTip = "\(save.title) – i skjermbildemappen (⌘S)"
    }

    private func lineImage(width: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 2, y: r.midY))
            p.line(to: NSPoint(x: r.maxX - 2, y: r.midY))
            p.lineWidth = width * 0.8
            p.lineCapStyle = .round
            NSColor.black.setStroke()
            p.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }

    // MARK: Valg

    func select(tool: Tool) {
        if tool != .text { canvas.commitText() }
        if tool != .select { canvas.selection = nil }
        toolControl.selectedSegment = tool.rawValue
        canvas.tool = tool
        Self.lastTool = tool
        textControls.isHidden = tool != .text
        redactControl.isHidden = tool != .redact
        widthControl.isHidden = tool == .text || tool == .redact || tool == .select
    }

    func select(colorIndex i: Int) { apply(color: Self.palette[i]) }

    private func apply(color: NSColor) {
        canvas.recolorSelection(color)
        canvas.color = color
        Self.lastColor = color
        colorWell.color = color
        for s in swatches { s.selected = s.swatch == color }
    }

    private func applyTextStyleToControls(_ s: TextStyle) {
        fontPopup.selectItem(at: TextFonts.all.firstIndex { $0.family == s.family } ?? 0)
        sizePopup.selectItem(at: TextFonts.sizes.firstIndex(of: s.size) ?? 2)
        boldButton.state = s.bold ? .on : .off
    }

    @objc private func toolChanged() {
        if let t = Tool(rawValue: toolControl.selectedSegment) { select(tool: t) }
    }

    @objc private func swatchClicked(_ sender: SwatchButton) { apply(color: sender.swatch) }
    @objc private func colorWellChanged() { apply(color: colorWell.color) }

    @objc private func widthChanged() {
        Self.lastWidth = widthControl.selectedSegment
        canvas.lineWidth = Self.widths[widthControl.selectedSegment]
    }

    @objc private func redactChanged() {
        let m = RedactMode(rawValue: redactControl.selectedSegment) ?? .pixelate
        Self.lastRedact = m
        canvas.redactMode = m
    }

    @objc private func textStyleChanged() {
        let s = TextStyle(family: TextFonts.all[max(0, fontPopup.indexOfSelectedItem)].family,
                          size: TextFonts.sizes[max(0, sizePopup.indexOfSelectedItem)],
                          bold: boldButton.state == .on)
        Self.lastTextStyle = s
        canvas.textStyle = s
    }

    // MARK: Handlinger

    @objc private func undoClicked() { undo() }

    func undo() {
        canvas.commitText()
        canvas.selection = nil
        doc.undo()
        refresh()
    }

    func redo() {
        canvas.commitText()
        canvas.selection = nil
        doc.redo()
        refresh()
    }

    private func refresh() {
        undoButton.isEnabled = doc.canUndo
        canvas.needsDisplay = true
    }

    /// Kopier-knappen (⌘C / ↩), etter innstillingen.
    @objc func copyClicked() {
        canvas.commitText()
        guard copyToPasteboard() else { return }
        switch Settings.shared.copyBehavior {
        case .copy:
            flash("Kopiert – lim inn i e-post eller chat")
        case .copyClose:
            window?.close()
        case .copySaveClose:
            if save() { window?.close() }
        }
    }

    /// Lagre-knappen (⌘S), etter innstillingen.
    @objc func saveClicked() {
        canvas.commitText()
        guard save() else { return }
        if Settings.shared.saveBehavior == .saveClose { window?.close() }
    }

    @objc func saveAsClicked() {
        canvas.commitText()
        guard let window else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.directoryURL = savedURL?.deletingLastPathComponent() ?? Settings.shared.folder
        p.nameFieldStringValue = (savedURL ?? Settings.shared.newScreenshotURL()).lastPathComponent
        p.beginSheetModal(for: window) { [weak self] r in
            guard let self, r == .OK, let url = p.url, self.write(to: url) else { return }
            if Settings.shared.saveBehavior == .saveClose { self.window?.close() }
        }
    }

    private func copyToPasteboard() -> Bool {
        guard let png = doc.renderPNG() else { flash("Kunne ikke lage bildet"); return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.writeObjects([item])
        return true
    }

    /// Lagrer i skjermbildemappen. Returnerer false ved feil (vinduet skal da ikke lukkes).
    @discardableResult
    func save() -> Bool {
        let url: URL
        if let savedURL {
            url = savedURL
        } else if temporary {
            do { try Settings.shared.ensureFolder() } catch { fail(error); return false }
            url = Settings.shared.newScreenshotURL()
        } else if doc.isEmpty {
            // Et eksisterende bilde uten tegninger er allerede lagret.
            return true
        } else {
            // Et eksisterende bilde overskrives ikke; første lagring blir en kopi ved siden av.
            let base = doc.url.deletingPathExtension().lastPathComponent + " – redigert"
            url = Settings.shared.newScreenshotURL(base: base, in: doc.url.deletingLastPathComponent())
        }
        return write(to: url)
    }

    private func write(to url: URL) -> Bool {
        guard let png = doc.renderPNG() else { flash("Kunne ikke lage bildet"); return false }
        do {
            try png.write(to: url, options: .atomic)
            savedURL = url
            window?.title = url.lastPathComponent
            window?.representedURL = url
            flash("Lagret: \(url.lastPathComponent)")
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func fail(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private var flashToken = 0
    private func flash(_ text: String) {
        flashToken += 1
        let token = flashToken
        statusLabel.stringValue = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.flashToken == token { self?.statusLabel.stringValue = "" }
        }
    }

    func windowWillClose(_ notification: Notification) {
        canvas.commitText()
        if temporary { try? FileManager.default.removeItem(at: doc.url) }
        NotificationCenter.default.removeObserver(self)
        onClose?()
    }
}
