import Foundation
import ImageIO
import CoreGraphics

// Build/run with:
// swiftc tools/extract_player_diagonal_frames.swift -o /tmp/extract_player_diagonal_frames
// /tmp/extract_player_diagonal_frames assets/art/characters/player_turnning.png assets/art/characters/player_diagonal_turn.png

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let columns = 4
let sourceFrameWidth = 100
let sourceFrameHeight = 225
let outputFrameWidth = 32
let outputFrameHeight = 72

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(
        data: nil,
        width: outputFrameWidth * columns,
        height: outputFrameHeight * 2,
        bitsPerComponent: 8,
        bytesPerRow: outputFrameWidth * columns * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fatalError("Unable to load source image")
}

context.clear(CGRect(x: 0, y: 0, width: outputFrameWidth * columns, height: outputFrameHeight * 2))
context.interpolationQuality = .none

// The source's lower row contains the two right-side diagonal poses:
// columns 4...7 face away (upper-right), and columns 0...3 face toward
// the camera (lower-right). Keep the output rows in gameplay order.
let sourceColumns = [4, 0]
for outputRow in 0..<2 {
    for column in 0..<columns {
        let sourceRect = CGRect(
            x: (sourceColumns[outputRow] + column) * sourceFrameWidth,
            y: sourceFrameHeight,
            width: sourceFrameWidth,
            height: sourceFrameHeight
        )
        guard let frame = image.cropping(to: sourceRect) else { fatalError("Unable to crop frame") }
        let destinationRect = CGRect(
            x: column * outputFrameWidth,
            y: (1 - outputRow) * outputFrameHeight,
            width: outputFrameWidth,
            height: outputFrameHeight
        )
        context.draw(frame, in: destinationRect)
    }
}

guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Unable to create output image")
}
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write output image") }
print("Wrote \(output.path)")
