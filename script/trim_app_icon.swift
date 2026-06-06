import AppKit
import CoreGraphics
import Foundation

struct Pixel {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: swift script/trim_app_icon.swift input.png output.png")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let image = NSImage(contentsOf: inputURL),
      let sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("Could not read image: \(inputURL.path)")
}

let width = sourceCGImage.width
let height = sourceCGImage.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("Could not create bitmap context")
}

context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

var minX = width
var minY = height
var maxX = 0
var maxY = 0

for y in 0..<height {
    for x in 0..<width {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let pixel = Pixel(
            r: pixels[offset],
            g: pixels[offset + 1],
            b: pixels[offset + 2],
            a: pixels[offset + 3]
        )
        let brightness = Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
        let isVisibleSubject = pixel.a > 16 && brightness > 36
        if isVisibleSubject {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

guard minX <= maxX, minY <= maxY else {
    fail("Could not find visible icon content")
}

let contentWidth = maxX - minX + 1
let contentHeight = maxY - minY + 1
let side = max(contentWidth, contentHeight)
let padding = Int(Double(side) * 0.018)
let cropSide = min(max(side + padding * 2, 1), min(width, height))
let centerX = (minX + maxX) / 2
let centerY = (minY + maxY) / 2
let cropX = max(0, min(width - cropSide, centerX - cropSide / 2))
let cropY = max(0, min(height - cropSide, centerY - cropSide / 2))

guard let cropped = sourceCGImage.cropping(to: CGRect(x: cropX, y: cropY, width: cropSide, height: cropSide)) else {
    fail("Could not crop image")
}

let targetSize = NSSize(width: 1024, height: 1024)
let outputImage = NSImage(size: targetSize)
outputImage.lockFocus()
let graphicsContext = NSGraphicsContext.current
graphicsContext?.imageInterpolation = .high
NSColor.clear.setFill()
let targetRect = NSRect(origin: .zero, size: targetSize)
targetRect.fill()

let iconRect = targetRect.insetBy(dx: 10, dy: 10)
let iconShape = NSBezierPath(roundedRect: iconRect, xRadius: 214, yRadius: 214)
NSGraphicsContext.saveGraphicsState()
iconShape.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.78, alpha: 1),
    NSColor(calibratedRed: 0.58, green: 0.54, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.63, green: 0.93, blue: 1.0, alpha: 1)
])?.draw(in: iconRect, angle: 315)

let expandedDrawRect = targetRect.insetBy(dx: -2, dy: -2)
NSImage(cgImage: cropped, size: targetSize).draw(in: expandedDrawRect)
NSGraphicsContext.restoreGraphicsState()
outputImage.unlockFocus()

guard let tiff = outputImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fail("Could not encode PNG")
}

try png.write(to: outputURL, options: .atomic)
print("Trimmed icon from \(width)x\(height), crop x=\(cropX) y=\(cropY) size=\(cropSide)")
