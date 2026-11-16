import Foundation

struct LEGOSet: Codable, Hashable, Identifiable, Sendable {
    let setNum: String
    let name: String
    let year: Int
    let numParts: Int
    let setImgUrl: URL?
    var id: String { setNum }
    var isSample: Bool { setNum == "sample-1" }
}

struct BrickPart: Codable, Hashable, Sendable {
    let partNum: String
    let name: String
    let partImgUrl: URL?
}

struct BrickColor: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let rgb: String
}

struct InventoryPart: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let part: BrickPart
    let color: BrickColor
    let quantity: Int
    let isSpare: Bool
    let elementId: String?
}

struct SavedBuild: Codable, Identifiable, Sendable {
    let set: LEGOSet
    let parts: [InventoryPart]
    var found: [String: Int] = [:]
    let addedAt: Date
    var id: String { self.set.id }
    var requiredParts: [InventoryPart] { parts.filter { !$0.isSpare } }
    var totalCount: Int { requiredParts.reduce(0) { $0 + $1.quantity } }
    var foundCount: Int { requiredParts.reduce(0) { $0 + count(for: $1) } }
    var progress: Double { totalCount == 0 ? 0 : Double(foundCount) / Double(totalCount) }
    var isComplete: Bool { totalCount > 0 && foundCount == totalCount }

    func count(for part: InventoryPart) -> Int {
        min(part.quantity, max(0, found[String(part.id), default: 0]))
    }

    mutating func setCount(_ count: Int, for part: InventoryPart) {
        guard parts.contains(where: { $0.id == part.id }) else { return }
        found[String(part.id)] = min(part.quantity, max(0, count))
    }

    mutating func toggle(_ part: InventoryPart) {
        setCount(count(for: part) == part.quantity ? 0 : part.quantity, for: part)
    }
}

enum SampleCatalog {
    static let set = LEGOSet(setNum: "sample-1", name: "Little brick house", year: 2026,
                            numParts: 32, setImgUrl: nil)
    // An original practice inventory, deliberately not attributed to an official LEGO set.
    static let parts: [InventoryPart] = [
        item(1, "3001", "Brick 2 × 4", "Warm yellow", "F4BE37", 14, 8),
        item(2, "3001", "Brick 2 × 4", "Coral red", "D9523B", 4, 6),
        item(3, "3003", "Brick 2 × 2", "White", "F1F0E8", 15, 4),
        item(4, "3020", "Plate 2 × 4", "Forest green", "427B5C", 2, 4),
        item(5, "3039", "Slope 45° 2 × 2", "Coral red", "D9523B", 4, 8),
        item(6, "3069b", "Tile 1 × 2", "Sky blue", "70A9C5", 9, 2)
    ]
    static func item(_ id: Int, _ number: String, _ name: String, _ color: String,
                     _ rgb: String, _ colorID: Int, _ quantity: Int) -> InventoryPart {
        InventoryPart(id: id, part: BrickPart(partNum: number, name: name, partImgUrl: nil),
                      color: BrickColor(id: colorID, name: color, rgb: rgb),
                      quantity: quantity, isSpare: false, elementId: nil)
    }
}
