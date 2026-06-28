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
    /// The brush footprint this tool paints with. Tools with no adjustable
    /// width are a single pixel.
    var size: PixelSize { get }
}

public extension Tool {
    var size: PixelSize { PixelSize(width: 1, height: 1) }
}

/// A tool whose brush width the user can adjust.
public protocol SizableTool: Tool {
    var width: Int { get set }
    /// The largest width this tool supports.
    var maxWidth: Int { get }
}

public extension SizableTool {
    var size: PixelSize { PixelSize(width: width, height: width) }
}

public struct PencilTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 10 }

    public init(width: Int) {
        self.width = width
    }
}
public struct EraserTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 10 }

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
public struct HighlightTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 5 }

    public init(width: Int) {
        self.width = width
    }
}
public struct ShadowTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 5 }

    public init(width: Int) {
        self.width = width
    }
}
public struct EyedroperTool: Tool {
    public init() { }
}
