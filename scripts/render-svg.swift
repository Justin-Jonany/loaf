// Rasterizes an SVG to a square PNG using AppKit's built-in SVG support, so regenerating
// the icons needs no image tooling beyond the Swift toolchain the build already requires.
//
//     swift scripts/render-svg.swift <in.svg> <out.png> <pixels>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let pixels = Int(args[3]) else {
    FileHandle.standardError.write("usage: render-svg.swift <in.svg> <out.png> <pixels>\n".data(using: .utf8)!)
    exit(2)
}
guard let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("couldn't load \(args[1])\n".data(using: .utf8)!)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
NSGraphicsContext.restoreGraphicsState()

do {
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
} catch {
    FileHandle.standardError.write("couldn't write \(args[2]): \(error)\n".data(using: .utf8)!)
    exit(1)
}
