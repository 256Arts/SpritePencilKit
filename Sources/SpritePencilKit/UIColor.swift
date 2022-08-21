//
//  UIColor.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2019-06-06.
//  Copyright © 2019 Jayden Irwin. All rights reserved.
//

import UIKit

public extension UIColor {
    
    convenience init(components: ColorComponents) {
        let red = CGFloat(components.red) / 255.0
        let green = CGFloat(components.green) / 255.0
        let blue = CGFloat(components.blue) / 255.0
        let alpha = CGFloat(components.opacity) / 255.0
        
        if components.colorSpace == .displayP3 {
            self.init(displayP3Red: red, green: green, blue: blue, alpha: alpha)
        } else {
            self.init(red: red, green: green, blue: blue, alpha: alpha)
        }
    }
    
}
