//
//  CGContext.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2018-10-04.
//  Copyright © 2018 Jayden Irwin. All rights reserved.
//

import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

public extension CGContext {

    func clear() {
        clear(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
    }

    /// Creates an empty pixel-art drawing context for the engine to draw into.
    ///
    /// The engine reads and writes pixels directly through `ContextDataManager`,
    /// which assumes a BGRA, premultiplied-first, little-endian, **sRGB** buffer.
    /// Building the context here — instead of via `UIGraphicsBeginImageContext`,
    /// which is *device RGB* — keeps painted colors, the eyedropper, and the
    /// saved PNG all in one color space, so colors round-trip exactly.
    static func spriteDrawingContext(width: Int, height: Int) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo)
    }

    #if canImport(UIKit)
    /// Creates a pixel-art drawing context seeded with `image`, normalizing it to
    /// the engine's sRGB buffer so eyedropped colors match the palette.
    static func spriteDrawingContext(from image: UIImage) -> CGContext? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard let context = spriteDrawingContext(width: width, height: height) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }
    #endif

    /// Creates an empty context with this context's exact pixel format (color
    /// space, byte order, alpha) for resize operations like rotate/trim. The
    /// engine's pointer math assumes BGRA little-endian, so recreating a context
    /// from `alphaInfo` alone would drop the byte order and channel-swap
    /// red/blue on every subsequent paint.
    func makeMatchingContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0, space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo.rawValue)
    }

}
