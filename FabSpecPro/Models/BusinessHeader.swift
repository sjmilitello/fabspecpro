import Foundation
import SwiftData

@Model
final class BusinessHeader {
    var id: UUID
    var businessName: String
    var address: String
    var email: String
    var phone: String
    var logoData: Data?

    init() {
        self.id = UUID()
        self.businessName = ""
        self.address = ""
        self.email = ""
        self.phone = ""
        self.logoData = nil
    }
}

@Model
final class MaterialOption {
    var id: UUID
    var name: String

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

enum MaterialThickness: String, CaseIterable, Identifiable, Codable {
    case twoCentimeter = "2 cm"
    case threeCentimeter = "3 cm"

    var id: String { rawValue }
}

enum ShapeKind: String, CaseIterable, Identifiable, Codable {
    case rectangle = "Rectangle"
    case circle = "Circle"
    case quarterCircle = "1/4 Circle"
    case rightTriangle = "Right Triangle"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .rightTriangle:
            return "Triangle"
        default:
            return rawValue
        }
    }
}

enum EdgePosition: String, CaseIterable, Identifiable, Codable {
    case top
    case right
    case bottom
    case left
    case hypotenuse
    case legA
    case legB

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Top"
        case .right: return "Right"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .hypotenuse: return "Hypotenuse"
        case .legA: return "Leg A"
        case .legB: return "Leg B"
        }
    }
}

enum CutoutKind: String, CaseIterable, Identifiable, Codable {
    case circle = "Circle"
    case rectangle = "Rectangle"
    case square = "Square"

    var id: String { rawValue }
}
