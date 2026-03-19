//
//  PieceDefaults.swift
//  FabSpecPro
//

import Foundation
import SwiftData

@Model
final class PieceDefaults {
    var id: UUID = UUID()

    // Basic defaults
    var defaultMaterialName: String = ""
    var defaultThickness: String = "3 cm"
    var defaultShape: String = "Rectangle"
    var defaultWidth: String = "24"
    var defaultHeight: String = "18"
    var defaultQuantity: Int = 1

    // Cutout defaults (optional - applied when adding cutout)
    var enableDefaultCutout: Bool = false
    var defaultCutoutShape: String = "Circle"  // Circle or Rectangle
    var defaultCutoutWidth: Double = 2.0
    var defaultCutoutHeight: Double = 2.0

    // Curve defaults (optional - applied when adding curve)
    var enableDefaultCurve: Bool = false
    var defaultCurveRadius: Double = 2.0
    var defaultCurveIsConcave: Bool = false
    var defaultCurveStartCorner: Int = -1  // -1 means "None"
    var defaultCurveEndCorner: Int = -1    // -1 means "None"

    // Angle defaults (optional - applied when adding angle)
    var enableDefaultAngle: Bool = false
    var defaultAngleDegrees: Double = 45.0
    var defaultAngleEdge1: Double = 2.0
    var defaultAngleEdge2: Double = 2.0
    var defaultAngleCorner: Int = -1  // -1 means "None"

    // Corner radius defaults (optional - applied when adding corner radius)
    var enableDefaultCornerRadius: Bool = false
    var defaultCornerRadiusValue: Double = 1.0
    var defaultCornerRadiusIsInside: Bool = false
    var defaultCornerRadiusCorner: Int = -1  // -1 means "None"

    init() {}
}
