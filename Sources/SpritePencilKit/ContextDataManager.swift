//
//  ContextDataSnapshot.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2019-07-29.
//  Copyright © 2019 Jayden Irwin. All rights reserved.
//

import CoreGraphics

public struct ContextDataManager {

    public var dataPointer: UnsafeMutablePointer<UInt8>

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

    public func dataOffset(for point: PixelPoint) -> Int {
        assert(0 <= point.x && point.x < width && 0 <= point.y && point.y < height,
               "Pixel (\(point.x), \(point.y)) is outside the \(width)×\(height) canvas")
        return (point.y * bytesPerRow) + (point.x * bytesPerPixel)
    }

}
