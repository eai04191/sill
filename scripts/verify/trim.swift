import AppKit
// Usage: trim <png>  Crops the image in place to its pixels that are not fully transparent. A popup's window covers the
// screen and is transparent outside the popup, so its capture is mostly empty.
guard CommandLine.arguments.count == 2 else { print("Usage: trim <png>"); exit(1) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let rep = NSBitmapImageRep(data: try Data(contentsOf: url)), let image = rep.cgImage else {
    print("Cannot read \(url.path)"); exit(1)
}
let width = image.width, height = image.height
// Draws into a known layout, premultiplied RGBA with 8 bits a channel, so the alpha is every fourth byte.
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] != 0 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= 0 else { print("\(url.path) is fully transparent"); exit(0) }
// The context's rows run from the top, as CGImage cropping expects.
let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
try NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])!.write(to: url)
