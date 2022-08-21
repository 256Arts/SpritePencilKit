//
//  PixelPoint.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2018-10-01.
//  Copyright © 2018 Jayden Irwin. All rights reserved.
//

import Foundation

public struct PixelPoint: Equatable, Hashable {
    public var x: Int
    public var y: Int
    
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct PixelSize: Equatable, Hashable {
    public var width: Int
    public var height: Int
    
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
