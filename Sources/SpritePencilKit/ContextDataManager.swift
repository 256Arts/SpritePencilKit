//
//  ContextDataSnapshot.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2019-07-29.
//  Copyright © 2019 Jayden Irwin. All rights reserved.
//

import CoreGraphics

public struct ContextDataManager {
    
    public var rowOffset: Int
    public var dataPointer: UnsafeMutablePointer<UInt8>
    
    public init(context: CGContext) {
        let widthMultiple = 8
        rowOffset = ((context.width + widthMultiple - 1) / widthMultiple) * widthMultiple // Round up to multiple of 8
        dataPointer = {
            let capacity = context.width * context.height
            let pointer = context.data!.bindMemory(to: UInt8.self, capacity: capacity)
            return pointer
        }()
    }
    
    public func dataOffset(for point: PixelPoint) -> Int {
        return 4 * ((point.y * rowOffset) + point.x)
    }
    
}
