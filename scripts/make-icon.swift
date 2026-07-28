#!/usr/bin/env swift
import Foundation
import CoreGraphics
import CoreText
import ImageIO

let size = CGSize(width: 1024, height: 1024)
let scale = size.width

func drawIcon(at pixelSize: Int) -> CGImage {
    let s = CGFloat(pixelSize)
    let rect = CGRect(origin: .zero, size: CGSize(width: s, height: s))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Unable to create CGContext")
    }

    let inset = s * 0.18
    let gaugeRect = rect.insetBy(dx: inset, dy: inset * 1.15)
    let center = CGPoint(x: rect.midX, y: rect.midY + s * 0.08)
    let radius = min(gaugeRect.width, gaugeRect.height) / 2

    // Background: rounded rect, macOS icon style
    let corner = s * 0.18
    let bgPath = CGPath(roundedRect: rect.insetBy(dx: s * 0.06, dy: s * 0.06), cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0))
    ctx.fillPath()

    // Gauge arc background
    let startAngle = CGFloat.pi * 0.8
    let endAngle = CGFloat.pi * 2.2
    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.addPath(arcPath)
    ctx.setStrokeColor(CGColor(red: 0.25, green: 0.27, blue: 0.30, alpha: 1.0))
    ctx.setLineWidth(s * 0.08)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Colored progress arc (0..1 mapped to angle)
    let progress: CGFloat = 0.55
    let progressEnd = startAngle + (endAngle - startAngle) * progress
    let progPath = CGMutablePath()
    progPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: progressEnd, clockwise: false)
    ctx.addPath(progPath)
    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.80, blue: 0.40, alpha: 1.0))
    ctx.setLineWidth(s * 0.08)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Needle
    let needleAngle = startAngle + (endAngle - startAngle) * progress
    let needleLen = radius * 0.85
    let needleEnd = CGPoint(
        x: center.x + needleLen * cos(needleAngle),
        y: center.y + needleLen * sin(needleAngle)
    )
    ctx.move(to: CGPoint(x: center.x, y: center.y))
    ctx.addLine(to: needleEnd)
    ctx.setStrokeColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0))
    ctx.setLineWidth(s * 0.045)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Center pivot
    ctx.addEllipse(in: CGRect(x: center.x - s * 0.06, y: center.y - s * 0.06, width: s * 0.12, height: s * 0.12))
    ctx.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0))
    ctx.fillPath()

    guard let image = ctx.makeImage() else {
        fatalError("Unable to make CGImage")
    }
    return image
}

let outRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/AppIcon.iconset")
try? FileManager.default.removeItem(at: outRoot)
try FileManager.default.createDirectory(at: outRoot, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for base in sizes {
    let img = drawIcon(at: base)
    let url = outRoot.appendingPathComponent("icon_\(base)x\(base).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Cannot create PNG destination")
    }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)

    if base <= 512 {
        let img2x = drawIcon(at: base * 2)
        let url2x = outRoot.appendingPathComponent("icon_\(base)x\(base)@2x.png")
        guard let dest2x = CGImageDestinationCreateWithURL(url2x as CFURL, "public.png" as CFString, 1, nil) else {
            fatalError("Cannot create PNG destination")
        }
        CGImageDestinationAddImage(dest2x, img2x, nil)
        CGImageDestinationFinalize(dest2x)
    }
}

print("Wrote iconset to \(outRoot.path)")
