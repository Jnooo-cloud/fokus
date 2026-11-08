// Draws the disk image background: drag arrow plus the one-time Gatekeeper step.
//   swift scripts/dmg-background.swift <out.png>
import AppKit

let size = NSSize(width: 640, height: 440)
let image = NSImage(size: size)
image.lockFocus()
NSColor(white: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func text(_ string: String, _ point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black, width: CGFloat = 560) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineSpacing = 3
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
    NSAttributedString(string: string, attributes: attributes)
        .draw(in: NSRect(x: point.x - width / 2, y: point.y, width: width, height: 80))
}

// Icons sit at y = 170 from the top (Finder coordinates), so y = 270 here.
text("Drag Fokus into Applications", NSPoint(x: 320, y: 340), size: 17, weight: .semibold)
text("Fokus in den Programme-Ordner ziehen", NSPoint(x: 320, y: 318), size: 12, color: NSColor(white: 0.45, alpha: 1))
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 265, y: 270)); arrow.line(to: NSPoint(x: 370, y: 270))
arrow.move(to: NSPoint(x: 355, y: 282)); arrow.line(to: NSPoint(x: 372, y: 270)); arrow.line(to: NSPoint(x: 355, y: 258))
arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(red: 0.42, green: 0.33, blue: 0.95, alpha: 1).setStroke()
arrow.stroke()

let box = NSBezierPath(roundedRect: NSRect(x: 40, y: 30, width: 560, height: 120), xRadius: 14, yRadius: 14)
NSColor.white.setFill(); box.fill()
NSColor(white: 0.86, alpha: 1).setStroke(); box.lineWidth = 1; box.stroke()
text("First launch: macOS blocks the app once", NSPoint(x: 320, y: 50), size: 13.5, weight: .semibold)
text("1. Open Fokus, close the warning with “Done”\n2. System Settings → Privacy & Security → scroll down\n3. Next to “Fokus was blocked”, click “Open Anyway” and enter your password",
     NSPoint(x: 320, y: 10), size: 12, color: NSColor(white: 0.3, alpha: 1))
text("Deutsch: Fokus öffnen, „Fertig“ → Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“",
     NSPoint(x: 320, y: -56), size: 10.5, color: NSColor(white: 0.5, alpha: 1), width: 600)
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
