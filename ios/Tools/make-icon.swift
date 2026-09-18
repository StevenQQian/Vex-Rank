import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Turns a logo into an iOS app icon.
//
// Two things have to happen. The white border around the artwork is trimmed,
// and the white that remains in the corners - left behind because the artwork
// is a rounded square - is filled with the artwork's own background colour.
// iOS applies its own rounded mask, so without that fill the finished icon
// shows four white slivers where the system's corners cut outside the logo's.
//
// The corner white is found by flooding inward from the edges rather than by
// replacing every white pixel, so white *inside* a logo is never eaten.

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source> <output.png> [size]\n".utf8))
    exit(2)
}
let sourcePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let size = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 1024

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("could not read \(sourcePath)\n".utf8))
    exit(1)
}

let width = image.width, height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let context = CGContext(data: &pixels, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func isWhitish(_ x: Int, _ y: Int) -> Bool {
    let i = (y * width + x) * 4
    // Transparent counts too: a logo exported with an alpha border is the same
    // problem wearing a different hat.
    if pixels[i + 3] < 24 { return true }
    return pixels[i] > 233 && pixels[i + 1] > 233 && pixels[i + 2] > 233
}

// Flood from every edge pixel; whatever is reached is background.
var background = [Bool](repeating: false, count: width * height)
var stack: [(Int, Int)] = []
for x in 0..<width { stack.append((x, 0)); stack.append((x, height - 1)) }
for y in 0..<height { stack.append((0, y)); stack.append((width - 1, y)) }
while let (x, y) = stack.popLast() {
    guard x >= 0, y >= 0, x < width, y < height else { continue }
    let index = y * width + x
    guard !background[index], isWhitish(x, y) else { continue }
    background[index] = true
    stack.append((x + 1, y)); stack.append((x - 1, y))
    stack.append((x, y + 1)); stack.append((x, y - 1))
}

// The artwork is whatever the flood did not reach.
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where !background[y * width + x] {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write(Data("the image is blank\n".utf8))
    exit(1)
}

// The fill colour: sampled from the middle of each edge of the artwork, where
// a rounded card is solid background. Sampling the whole border instead walks
// through the corners, which are either still white or half-way there, and the
// fill then lands a few shades off and leaves a visible ring.
var counts: [UInt32: Int] = [:]
let inset = max(2, (maxX - minX) / 16)
let centreXSample = (minX + maxX) / 2, centreYSample = (minY + maxY) / 2
let probes = [(centreXSample, minY + inset), (centreXSample, maxY - inset),
              (minX + inset, centreYSample), (maxX - inset, centreYSample)]
for (x, y) in probes where x >= 0 && y >= 0 && x < width && y < height && !isWhitish(x, y) {
    let i = (y * width + x) * 4
    let key = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
    counts[key, default: 0] += 1
}
let fill = counts.max(by: { $0.value < $1.value })?.key ?? 0
let fillR = UInt8((fill >> 16) & 0xFF), fillG = UInt8((fill >> 8) & 0xFF), fillB = UInt8(fill & 0xFF)

// Grow the background by a couple of pixels so the anti-aliased edge of the
// original card is painted over too; left alone it survives as a pale ring
// once the corners around it are filled.
for _ in 0..<2 {
    var grown = background
    for y in 0..<height {
        for x in 0..<width where !background[y * width + x] {
            let neighbours = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            if neighbours.contains(where: { nx, ny in
                nx >= 0 && ny >= 0 && nx < width && ny < height && background[ny * width + nx]
            }) {
                grown[y * width + x] = true
            }
        }
    }
    background = grown
}

for index in 0..<(width * height) where background[index] {
    pixels[index * 4] = fillR
    pixels[index * 4 + 1] = fillG
    pixels[index * 4 + 2] = fillB
    pixels[index * 4 + 3] = 255
}

guard let filled = context.makeImage() else { exit(1) }
// Crop to the artwork, squared off around its centre so nothing is stretched.
let side = max(maxX - minX + 1, maxY - minY + 1)
let centreX = (minX + maxX) / 2, centreY = (minY + maxY) / 2
let cropRect = CGRect(x: max(0, centreX - side / 2), y: max(0, centreY - side / 2),
                      width: min(side, width), height: min(side, height))
let cropped = filled.cropping(to: cropRect) ?? filled

// Icons carry no alpha, and the fill shows through anywhere the crop ran past
// the edge of the source.
guard let out = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
out.setFillColor(CGColor(red: CGFloat(fillR) / 255, green: CGFloat(fillG) / 255,
                         blue: CGFloat(fillB) / 255, alpha: 1))
out.fill(CGRect(x: 0, y: 0, width: size, height: size))
out.interpolationQuality = .high
out.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))

guard let final = out.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, final, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(outputPath) at \(size)x\(size), background #\(String(format: "%02X%02X%02X", fillR, fillG, fillB))")
