import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = root.appendingPathComponent("Questionio.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (size, name) in [(16,"icon_16x16"),(32,"icon_16x16@2x"),(32,"icon_32x32"),(64,"icon_32x32@2x"),(128,"icon_128x128"),(256,"icon_128x128@2x"),(256,"icon_256x256"),(512,"icon_256x256@2x"),(512,"icon_512x512"),(1024,"icon_512x512@2x")] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size)/1024); transform.concat()
    let box = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 220, yRadius: 220)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.68, blue: 0.7, alpha: 1), ending: NSColor(calibratedRed: 0.24, green: 0.22, blue: 0.66, alpha: 1))!
    gradient.draw(in: box, angle: -45)
    NSColor.white.setStroke()
    let circle = NSBezierPath(ovalIn: NSRect(x: 225, y: 260, width: 530, height: 530)); circle.lineWidth = 90; circle.stroke()
    let tail = NSBezierPath(); tail.move(to: NSPoint(x: 580,y: 405)); tail.line(to: NSPoint(x: 800,y: 210)); tail.lineWidth = 92; tail.lineCapStyle = .round; tail.stroke()
    let dot = NSBezierPath(ovalIn: NSRect(x: 460,y: 425,width: 72,height: 72)); NSColor.white.setFill(); dot.fill()
    let hook = NSBezierPath(); hook.move(to: NSPoint(x: 440,y: 655)); hook.curve(to: NSPoint(x: 545,y: 600), controlPoint1: NSPoint(x: 465,y: 715), controlPoint2: NSPoint(x: 625,y: 680)); hook.curve(to: NSPoint(x: 497,y: 555),controlPoint1: NSPoint(x: 535,y: 580),controlPoint2: NSPoint(x: 497,y: 595)); hook.lineWidth = 48; hook.lineCapStyle = .round; hook.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name+".png"))
}
