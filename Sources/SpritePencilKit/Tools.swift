//
//  Tools.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2019-06-06.
//  Copyright © 2019 Jayden Irwin. All rights reserved.
//

import CoreGraphics

public enum BrushShape: String, CaseIterable, Equatable, Hashable {
    case square
    case circle

    /// Whether the cell at `(column, row)` within a `diameter`×`diameter` brush
    /// is part of the brush mask. `column`/`row` are offsets from the brush's
    /// top-left corner. Square always fills; circle keeps cells whose center
    /// falls within the inscribed circle, tightened by half a pixel so the
    /// smallest round brush (3px) renders as a plus rather than a full square.
    /// Brushes 2px and smaller are solid blocks for both shapes (a round 1–2px
    /// brush has no meaningful curve).
    public func includes(column: Int, row: Int, diameter: Int) -> Bool {
        switch self {
        case .square:
            return true
        case .circle:
            guard diameter > 2 else { return true }
            let radius = Double(diameter) / 2.0
            let dx = Double(column) + 0.5 - radius
            let dy = Double(row) + 0.5 - radius
            return dx * dx + dy * dy <= radius * radius - 0.5
        }
    }
}

public protocol Tool {

}

public struct PencilTool: Tool {
    public var width: Int
    public var size: PixelSize {
        return PixelSize(width: width, height: width)
    }
    
    public init(width: Int) {
        self.width = width
    }
}
public struct EraserTool: Tool {
    public var width: Int
    public var size: PixelSize {
        return PixelSize(width: width, height: width)
    }
    
    public init(width: Int) {
        self.width = width
    }
}
public struct FillTool: Tool {
    public init() { }
}
public struct MoveTool: Tool {
    public init() { }
}
public struct HighlightTool: Tool {
    public var width: Int
    public var size: PixelSize {
        return PixelSize(width: width, height: width)
    }
    
    public init(width: Int) {
        self.width = width
    }
}
public struct ShadowTool: Tool {
    public var width: Int
    public var size: PixelSize {
        return PixelSize(width: width, height: width)
    }
    
    public init(width: Int) {
        self.width = width
    }
}
public struct EyedroperTool: Tool {
    public init() { }
}
