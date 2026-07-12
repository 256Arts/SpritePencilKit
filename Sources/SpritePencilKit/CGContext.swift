//
//  CGContext.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2018-10-04.
//  Copyright © 2018 Jayden Irwin. All rights reserved.
//

import CoreGraphics

public extension CGContext {
    
    func clear() {
        clear(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
    }

    /// Creates an empty context with this context's exact pixel format (color
    /// space, byte order, alpha) for resize operations like rotate/trim. The
    /// engine's pointer math assumes BGRA little-endian, so recreating a context
    /// from `alphaInfo` alone would drop the byte order and channel-swap
    /// red/blue on every subsequent paint.
    func makeMatchingContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0, space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo.rawValue)
    }

}
