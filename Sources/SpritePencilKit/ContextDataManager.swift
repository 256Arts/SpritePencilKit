//
//  ContextDataManager.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2019-07-29.
//  Copyright © 2019 Jayden Irwin. All rights reserved.
//

import CoreGraphics

/// Bounds-checked pixel access to a BGRA (little-endian) drawing context's
/// backing buffer. All reads and writes of canvas pixels go through the
/// subscript — the raw pointer never escapes.
public struct ContextDataManager {

    private let dataPointer: UnsafeMutablePointer<UInt8>

    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    private let bytesPerPixel: Int

    public init(context: CGContext) {
        width = context.width
        height = context.height
        bytesPerRow = context.bytesPerRow
        bytesPerPixel = context.bitsPerPixel / 8
        // The buffer spans full rows (including any alignment padding), not
        // width × height pixels.
        dataPointer = context.data!.bindMemory(to: UInt8.self, capacity: context.height * context.bytesPerRow)
    }

    public subscript(point: PixelPoint) -> ColorComponents {
        get {
            let offset = dataOffset(for: point)
            return ColorComponents(red: dataPointer[offset+2], green: dataPointer[offset+1], blue: dataPointer[offset], opacity: dataPointer[offset+3])
        }
        nonmutating set {
            let offset = dataOffset(for: point)
            dataPointer[offset+2] = newValue.red
            dataPointer[offset+1] = newValue.green
            dataPointer[offset] = newValue.blue
            dataPointer[offset+3] = newValue.opacity
        }
    }

    private func dataOffset(for point: PixelPoint) -> Int {
        assert(0 <= point.x && point.x < width && 0 <= point.y && point.y < height,
               "Pixel (\(point.x), \(point.y)) is outside the \(width)×\(height) canvas")
        return (point.y * bytesPerRow) + (point.x * bytesPerPixel)
    }

}
