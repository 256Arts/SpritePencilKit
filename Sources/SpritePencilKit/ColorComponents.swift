//
//  ColorComponents.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2019-06-06.
//  Copyright © 2019 Jayden Irwin. All rights reserved.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct ColorComponents: Equatable, Hashable, Identifiable, Sendable {
    
    public static let clear = ColorComponents(red: 0, green: 0, blue: 0, opacity: 0)
    
    public let colorSpace: Color.RGBColorSpace
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let opacity: UInt8
    
    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, red: UInt8, green: UInt8, blue: UInt8, opacity: UInt8) {
        self.colorSpace = colorSpace
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
    
    public init?(hex: String) {
        let string: String
        if hex.hasPrefix("#") {
            string = String(hex.dropFirst())
        } else {
            string = hex
        }
        
        let scanner = Scanner(string: string)
        var hexNumber: UInt64 = 0
        
        colorSpace = .sRGB
        switch string.count {
        case 8:
            if scanner.scanHexInt64(&hexNumber) {
                red = UInt8((hexNumber & 0xff000000) >> 24)
                green = UInt8((hexNumber & 0x00ff0000) >> 16)
                blue = UInt8((hexNumber & 0x0000ff00) >> 8)
                opacity = UInt8(hexNumber & 0x000000ff)
                return
            }
        case 6:
            if scanner.scanHexInt64(&hexNumber) {
                red = UInt8((hexNumber & 0xff0000) >> 16)
                green = UInt8((hexNumber & 0x00ff00) >> 8)
                blue = UInt8(hexNumber & 0x0000ff)
                opacity = 255
                return
            }
        case 4:
            if scanner.scanHexInt64(&hexNumber) {
                red = UInt8((hexNumber & 0xf000) >> 12)
                green = UInt8((hexNumber & 0x0f00) >> 8)
                blue = UInt8((hexNumber & 0x00f0) >> 4)
                opacity = UInt8(hexNumber & 0x000f)
                return
            }
        case 3:
            if scanner.scanHexInt64(&hexNumber) {
                red = UInt8((hexNumber & 0xf00) >> 8)
                green = UInt8((hexNumber & 0x0f0) >> 4)
                blue = UInt8(hexNumber & 0x00f)
                opacity = 255
                return
            }
        default:
            return nil
        }
        return nil
    }
    
    #if canImport(UIKit)
    /// Creates sRGB color components from a SwiftUI `Color`.
    ///
    /// Each channel is clamped to `0...1` and rounded to the nearest 8-bit
    /// value. Wide-gamut colors resolve to *extended* sRGB channels that can
    /// fall outside `0...1`; without clamping the `UInt8` conversion would trap,
    /// and truncating (rather than rounding) yielded slightly-off colors that
    /// failed to round-trip. This is the inverse of `Color(components:)`.
    public init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func channel(_ value: CGFloat) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        self.init(.sRGB, red: channel(red), green: channel(green), blue: channel(blue), opacity: channel(alpha))
    }
    #endif

    /// "#RRGGBB" (opacity is not encoded). The inverse of `init(hex:)`.
    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Canonical packed RGBA. Every fully-transparent value collapses to 0 so
    /// equality, hashing, and identity agree that "clear is clear" — hashing
    /// anything more than `==` compares is undefined behavior in Set/Dictionary.
    public var id: UInt32 {
        opacity == 0 ? 0 : UInt32(red) << 24 | UInt32(green) << 16 | UInt32(blue) << 8 | UInt32(opacity)
    }

    public static func ==(left: ColorComponents, right: ColorComponents) -> Bool {
        left.id == right.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
