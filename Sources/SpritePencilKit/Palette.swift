//
//  Palette.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2018-10-01.
//  Copyright © 2018 Jayden Irwin. All rights reserved.
//

import UIKit

public class Palette: Equatable {
    
    public enum SpecialCase {
        case rrggbb, hhhhssbb, rrrgggbb
    }
    
    public static let sp16 = Palette(name: "SP 16", specialCase: nil, colors: {
        let rgb: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (255, 255, 255),(170, 170, 170),(85, 85, 85),(0, 0, 0),
            (178, 36, 25),(255, 51, 41),(255, 148, 0),(255, 204, 0),
            (56, 161, 61),(76, 217, 99),(75, 190, 255),(20, 122, 245),
            (89, 87, 214),(255, 128, 198),(230, 185, 140),(140, 90, 40)
        ]
        return rgb.map({ ColorComponents(red: $0.r, green: $0.g, blue: $0.b, opacity: 255) })
    }(), defaultGroupLength: 1)
    public static let rrggbb = Palette(name: "RRGGBB", specialCase: .rrggbb, colors: {
        var colors = [ColorComponents]()
        for red in 0..<4 {
                for green in 0..<4 {
                    for blue in 0..<4 {
                        colors.append(ColorComponents(red: UInt8(red)*(255/3), green: UInt8(green)*(255/3), blue: UInt8(blue)*(255/3), opacity: 255))
                    }
                }
            }
            //        case "RRGGBB - P3":
            //            for red in 0..<4 {
            //                for green in 0..<4 {
            //                    for blue in 0..<4 {
            //                        colors.append(UIColor(displayP3Red: CGFloat(red)/3.0, green: CGFloat(green)/3.0, blue: CGFloat(blue)/3.0, opacity: 1.0))
            //                    }
            //                }
        //            }
        return colors
    }(), defaultGroupLength: 8)
    public static let hhhhssbb = Palette(name: "HHHHSSBB", specialCase: .hhhhssbb, colors: {
        var colors = [UIColor]()
        for saturation in stride(from: CGFloat(1.0), to: 0.33333, by: -0.33333) {
            for brightness in stride(from: CGFloat(1.0), to: 0.33333, by: -0.33333) {
                for hue in 0..<16 {
                    colors.append(UIColor(hue: CGFloat(hue)/16.0, saturation: saturation, brightness: brightness, alpha: 1.0))
                }
            }
        }
        for brightness in stride(from: CGFloat(1.0), to: 0.0, by: -0.33333) {
            colors.append(UIColor(hue: 0.0, saturation: 0.0, brightness: brightness, alpha: 1.0))
        }
        return colors.map({ color in
            var red: CGFloat = 0.0
            var green: CGFloat = 0.0
            var blue: CGFloat = 0.0
            var opacity: CGFloat = 0.0
            color.getRed(&red, green: &green, blue: &blue, alpha: &opacity)
            return ColorComponents(red: UInt8(red*255), green: UInt8(green*255), blue: UInt8(blue*255), opacity: 255)
        })
    }(), defaultGroupLength: 8)
    public static let rrrgggbb = Palette(name: "RRRGGGBB", specialCase: .rrrgggbb, colors: {
        var colors = [ColorComponents]()
        for red in 0..<8 {
                for green in 0..<8 {
                    for blue in 0..<4 {
                        colors.append(ColorComponents(red: UInt8(red)*(255/7), green: UInt8(green)*(255/7), blue: UInt8(blue)*(255/3), opacity: 255))
                    }
                }
            }
            //        case "RRRGGGBB - P3":
            //            for red in 0..<8 {
            //                for green in 0..<8 {
            //                    for blue in 0..<4 {
            //                        colors.append(UIColor(displayP3Red: CGFloat(red)/7.0, green: CGFloat(green)/7.0, blue: CGFloat(blue)/3.0, opacity: 1.0))
            //                    }
            //                }
        //            }
        return colors
    }(), defaultGroupLength: 8)
    
    public static func ==(_ lhs: Palette, _ rhs: Palette) -> Bool {
        return lhs.name == rhs.name
    }
    
    public var name: String
    public let specialCase: SpecialCase?
    public let colors: [ColorComponents]
    public let defaultGroupLength: Int
    public let groupLengths: [Int]
    
    public init(name: String, specialCase: SpecialCase?, colors: [ColorComponents], defaultGroupLength: Int, groupLengths: [Int] = []) {
        self.name = name
        self.specialCase = specialCase
        self.colors = colors
        self.defaultGroupLength = defaultGroupLength
        self.groupLengths = groupLengths
    }
    
    public init?(name: String, image: UIImage, defaultGroupLength: Int, groupLengths: [Int] = []) {
        guard image.size.height == 1 else { return nil }
        self.name = name
        self.specialCase = nil
        self.defaultGroupLength = defaultGroupLength
        self.groupLengths = groupLengths
        
        UIGraphicsBeginImageContext(image.size)
        image.draw(at: .zero)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        let contextDataManager = ContextDataManager(context: context)
        let cdp = contextDataManager.dataPointer
        var colors = [ColorComponents]()
        
        for x in 0..<context.width {
            let point = PixelPoint(x: x, y: 0)
            let offset = contextDataManager.dataOffset(for: point)
            let colorComp = ColorComponents(red: cdp[offset+2], green: cdp[offset+1], blue: cdp[offset], opacity: cdp[offset+3])
            colors.append(colorComp)
        }
        
        self.colors = colors
        UIGraphicsEndImageContext()
    }
    
    public func highlight(forColorComponents components: ColorComponents) -> ColorComponents {
        switch specialCase {
        case .rrggbb:
            // Increase components with value = 0 if nothing else can be increased
            let increaseZeros = (components.red == 0 || components.red == 255)
                && (components.green == 0 || components.green == 255)
                && (components.blue == 0 || components.blue == 255)
            
            let red: UInt8 = {
                if components.red == 0 {
                    return increaseZeros ? 255/3 : 0
                } else if 255 - components.red < 255/3 {
                    return 255
                } else {
                    return components.red + 255/3
                }
            }()
            let green: UInt8 = {
                if components.green == 0 {
                    return increaseZeros ? 255/3 : 0
                } else if 255 - components.green < 255/3 {
                    return 255
                } else {
                    return components.green + 255/3
                }
            }()
            let blue: UInt8 = {
                if components.blue == 0 {
                    return increaseZeros ? 255/3 : 0
                } else if 255 - components.blue < 255/3 {
                    return 255
                } else {
                    return components.blue + 255/3
                }
            }()
            return ColorComponents(red: red, green: green, blue: blue, opacity: components.opacity)
        case .rrrgggbb:
            // Increase components with value = 0 if nothing else can be increased
            let increaseZeros = (components.red == 0 || components.red == 255)
                && (components.green == 0 || components.green == 255)
                && (components.blue == 0 || components.blue == 255)
            
            let red: UInt8 = {
                if components.red == 0 {
                    return increaseZeros ? 255/7 : 0
                } else if 255 - components.red < 255/7 {
                    return 255
                } else {
                    return components.red + 255/7
                }
            }()
            let green: UInt8 = {
                if components.green == 0 {
                    return increaseZeros ? 255/7 : 0
                } else if 255 - components.green < 255/7 {
                    return 255
                } else {
                    return components.green + 255/7
                }
            }()
            let blue: UInt8 = {
                if components.blue == 0 {
                    return increaseZeros ? 255/3 : 0
                } else if 255 - components.blue < 255/3 {
                    return 255
                } else {
                    return components.blue + 255/3
                }
            }()
            return ColorComponents(red: red, green: green, blue: blue, opacity: components.opacity)
        default:
            let color = UIColor(components: components)
            var hue: CGFloat = 0.0
            var saturation: CGFloat = 0.0
            var brightness: CGFloat = 0.0
            var opacity: CGFloat = 1.0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)
            if brightness < 1.0 {
                brightness = min(brightness + 0.33333, 1.0)
            } else {
                saturation = max(0.0, saturation - 0.33333)
            }
            let newColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: opacity)
            var red: CGFloat = 0.0
            var green: CGFloat = 0.0
            var blue: CGFloat = 0.0
            newColor.getRed(&red, green: &green, blue: &blue, alpha: &opacity)
            return ColorComponents(red: UInt8(red*255), green: UInt8(green*255), blue: UInt8(blue*255), opacity: components.opacity)
        }
    }
    
    public func shadow(forColorComponents components: ColorComponents) -> ColorComponents {
        switch specialCase {
        case .rrggbb:
            let red: UInt8 = {
                if components.red < 255/3 {
                    return 0
                } else {
                    return components.red - 255/3
                }
            }()
            let green: UInt8 = {
                if components.green < 255/3 {
                    return 0
                } else {
                    return components.green - 255/3
                }
            }()
            let blue: UInt8 = {
                if components.blue < 255/3 {
                    return 0
                } else {
                    return components.blue - 255/3
                }
            }()
            return ColorComponents(red: red, green: green, blue: blue, opacity: components.opacity)
        case .rrrgggbb:
            let red: UInt8 = {
                if components.red < 255/7 {
                    return 0
                } else {
                    return components.red - 255/7
                }
            }()
            let green: UInt8 = {
                if components.green < 255/7 {
                    return 0
                } else {
                    return components.green - 255/7
                }
            }()
            let blue: UInt8 = {
                if components.blue < 255/3 {
                    return 0
                } else {
                    return components.blue - 255/3
                }
            }()
            return ColorComponents(red: red, green: green, blue: blue, opacity: components.opacity)
        default:
            let color = UIColor(components: components)
            var hue: CGFloat = 0.0
            var saturation: CGFloat = 0.0
            var brightness: CGFloat = 0.0
            var opacity: CGFloat = 1.0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)
            let newColor = UIColor(hue: hue, saturation: saturation, brightness: max(0.0, brightness - 0.33333), alpha: opacity)
            var red: CGFloat = 0.0
            var green: CGFloat = 0.0
            var blue: CGFloat = 0.0
            newColor.getRed(&red, green: &green, blue: &blue, alpha: &opacity)
            return ColorComponents(red: UInt8(red*255), green: UInt8(green*255), blue: UInt8(blue*255), opacity: components.opacity)
        }
    }
    
}
