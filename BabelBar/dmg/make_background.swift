// Фон окна установки (DMG).
//
// Рисует картинку 660×420, поверх которой Finder кладёт настоящие иконки:
// BabelBar.app слева, ярлык Applications справа. Поэтому сами иконки здесь
// НЕ рисуются — только подложка, надпись и стрелка между их местами.
//
// Запуск:  swift make_background.swift <папка-назначения>
// Результат: background.png (1x), background@2x.png (2x), background.tiff (обе в одном файле).
//
// Координаты в коде — от ЛЕВОГО ВЕРХНЕГО угла (как в Finder), пересчёт в систему
// AppKit (снизу вверх) делает функция `y()`. Точки центров иконок должны совпадать
// с `set position of item …` в dmg_build.sh.

import AppKit

let W: CGFloat = 660
let H: CGFloat = 420

/// Центры иконок в координатах Finder (левый верхний угол = 0,0).
let appIconCenter = CGPoint(x: 165, y: 170)
let dstIconCenter = CGPoint(x: 495, y: 170)

/// Перевод «сверху вниз» → «снизу вверх».
func y(_ top: CGFloat) -> CGFloat { H - top }
func p(_ x: CGFloat, _ top: CGFloat) -> CGPoint { CGPoint(x: x, y: y(top)) }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

let ink = rgb(0x0E1B3D)      // тёмно-синий — как фон иконки приложения
let muted = rgb(0x6C7A99)    // серо-синий
let accent = rgb(0x6B4BFF)   // фиолетовый акцент бренда

func draw() {
    // 1) Подложка: почти белый вертикальный градиент.
    NSGradient(colors: [rgb(0xFFFFFF), rgb(0xEEF2FA)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // 2) Мягкое фирменное свечение за иконкой приложения.
    let glow = NSGradient(colors: [accent.withAlphaComponent(0.16), accent.withAlphaComponent(0)])!
    glow.draw(fromCenter: p(appIconCenter.x, appIconCenter.y), radius: 0,
              toCenter: p(appIconCenter.x, appIconCenter.y), radius: 190, options: [])
    let glow2 = NSGradient(colors: [rgb(0x2F6BFF, 0.10), rgb(0x2F6BFF, 0)])!
    glow2.draw(fromCenter: p(dstIconCenter.x, dstIconCenter.y), radius: 0,
               toCenter: p(dstIconCenter.x, dstIconCenter.y), radius: 190, options: [])

    // 3) Дуга у нижнего края — отделяет «пол» окна, как в референсе.
    let arc = NSBezierPath()
    arc.move(to: p(-40, 392))
    arc.curve(to: p(W + 40, 392), controlPoint1: p(W * 0.3, 366), controlPoint2: p(W * 0.7, 366))
    arc.lineWidth = 1
    rgb(0xD8E0EE).setStroke()
    arc.stroke()

    // 4) Надпись «drag and drop» — по центру между иконками, на их высоте.
    let size: CGFloat = 30
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    let parts: [(String, NSColor)] = [("drag", ink), (" and ", muted), ("drop", accent)]
    let title = NSMutableAttributedString()
    for (text, color) in parts {
        title.append(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .kern: -0.4,
        ]))
    }
    let tSize = title.size()
    let cx = (appIconCenter.x + dstIconCenter.x) / 2
    title.draw(at: NSPoint(x: cx - tSize.width / 2, y: y(170) - tSize.height / 2 + 2))

    // 5) Стрелка от приложения к Applications: дуга, провисающая вниз.
    let start = p(248, 288)
    let end = p(424, 262)
    let c1 = p(300, 340)
    let c2 = p(378, 330)
    let curve = NSBezierPath()
    curve.move(to: start)
    curve.curve(to: end, controlPoint1: c1, controlPoint2: c2)
    curve.lineWidth = 9
    curve.lineCapStyle = .round
    ink.setStroke()
    curve.stroke()

    // Наконечник — по касательной к концу кривой (производная кубической Безье в t=1).
    let dir = CGVector(dx: end.x - c2.x, dy: end.y - c2.y)
    let len = max(sqrt(dir.dx * dir.dx + dir.dy * dir.dy), 0.001)
    let ux = dir.dx / len, uy = dir.dy / len
    let nx = -uy, ny = ux
    let tip = CGPoint(x: end.x + ux * 16, y: end.y + uy * 16)
    let head = NSBezierPath()
    head.move(to: tip)
    head.line(to: CGPoint(x: end.x - ux * 8 + nx * 15, y: end.y - uy * 8 + ny * 15))
    head.line(to: CGPoint(x: end.x - ux * 8 - nx * 15, y: end.y - uy * 8 - ny * 15))
    head.close()
    ink.setFill()
    head.fill()

    // 6) Подпись сверху — имя продукта, разрядка как в лендинге.
    let caption = NSAttributedString(string: "B A B E L B A R", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: muted.withAlphaComponent(0.75),
        .kern: 1.6,
    ])
    let cSize = caption.size()
    caption.draw(at: NSPoint(x: W / 2 - cSize.width / 2, y: y(46)))
}

func render(scale: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                              pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)   // задаёт масштаб рисования
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
render(scale: 1, to: outDir.appendingPathComponent("background.png"))
render(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))
print("ok")
