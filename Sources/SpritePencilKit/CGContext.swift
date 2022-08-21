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
    
}
