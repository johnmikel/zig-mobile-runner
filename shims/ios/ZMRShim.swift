import Foundation
import XCTest

struct ZMRShimCommand: Decodable {
    let cmd: String
    let selector: String?
    let text: String?
    let x: Int?
    let y: Int?
    let x1: Int?
    let y1: Int?
    let x2: Int?
    let y2: Int?
    let durationMs: UInt?
    let maxChars: UInt?
}

struct ZMRShimBounds: Encodable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct ZMRShimNode: Encodable {
    let id: String
    let type: String
    let label: String
    let identifier: String
    let bounds: ZMRShimBounds
    let enabled: Bool
    let visible: Bool
    let selected: Bool
}

enum ZMRShim {
    static func snapshot(app: XCUIApplication) -> [ZMRShimNode] {
        app.descendants(matching: .any).allElementsBoundByIndex.enumerated().map { index, element in
            let frame = element.frame
            return ZMRShimNode(
                id: stableId(index: index, element: element),
                type: String(describing: element.elementType),
                label: element.label,
                identifier: element.identifier,
                bounds: ZMRShimBounds(
                    x: Int(frame.origin.x),
                    y: Int(frame.origin.y),
                    width: Int(frame.size.width),
                    height: Int(frame.size.height)
                ),
                enabled: element.isEnabled,
                visible: element.exists && !frame.isEmpty,
                selected: element.isSelected
            )
        }
    }

    private static func stableId(index: Int, element: XCUIElement) -> String {
        if !element.identifier.isEmpty {
            return "id:\(element.identifier)"
        }
        if !element.label.isEmpty {
            return "label:\(element.label):\(index)"
        }
        return "index:\(index)"
    }
}

