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
    
    private var bytesPerRow: Int
    private var bytesPerPixel: Int
    
    public init(context: CGContext) {
        bytesPerRow = context.bytesPerRow
        bytesPerPixel = context.bitsPerPixel / 8
        dataPointer = {
            let capacity = context.width * context.height
            let pointer = context.data!.bindMemory(to: UInt8.self, capacity: capacity)
            return pointer
        }()
    }
    
    public func dataOffset(for point: PixelPoint) -> Int {
        return (point.y * bytesPerRow) + (point.x * bytesPerPixel)
    }
    
}
