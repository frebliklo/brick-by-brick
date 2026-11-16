import SwiftUI

/// Catalog photography when available; accurate basic shapes for the practice inventory.
/// Unknown parts never fall back to a misleading generic brick.
struct PartImage: View {
    let part: InventoryPart

    var body: some View {
        AsyncImage(url: part.part.partImgUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().blendMode(.multiply).padding(4)
            } else if let shape = BasicPartShape(partNumber: part.part.partNum) {
                BasicPartDrawing(shape: shape, color: Color(hex: part.color.rgb)).padding(8)
            } else {
                VStack(spacing: 8) {
                    if part.part.partImgUrl != nil, phase.error == nil {
                        ProgressView()
                        Text("Loading picture…")
                    } else {
                        Image(systemName: "photo").font(.title)
                        Text("Picture unavailable")
                    }
                    Text("#\(part.part.partNum)").font(.caption.monospaced())
                }
                .font(.caption).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .imageWell(cornerRadius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(part.color.name) \(part.part.name)")
    }
}

private struct BasicPartShape {
    let columns: Int
    let rows: Int
    let height: CGFloat
    var hasStuds = true
    var isSlope = false

    init?(partNumber: String) {
        switch partNumber {
        case "3001": self.init(columns: 4, rows: 2, height: 34)
        case "3003": self.init(columns: 2, rows: 2, height: 34)
        case "3020": self.init(columns: 4, rows: 2, height: 11)
        case "3039": self.init(columns: 2, rows: 2, height: 34, isSlope: true)
        case "3069b": self.init(columns: 2, rows: 1, height: 11, hasStuds: false)
        default: return nil
        }
    }

    private init(columns: Int, rows: Int, height: CGFloat, hasStuds: Bool = true, isSlope: Bool = false) {
        self.columns = columns
        self.rows = rows
        self.height = height
        self.hasStuds = hasStuds
        self.isSlope = isSlope
    }
}

private struct BasicPartDrawing: View {
    let shape: BasicPartShape
    let color: Color

    var body: some View {
        Canvas { context, size in
            let columns = CGFloat(shape.columns)
            let rows = CGFloat(shape.rows)
            let width = columns * 27 + rows * 23
            let height = columns * 12 + rows * 16 + shape.height + 13
            let scale = min(size.width / width, size.height / height)
            context.translateBy(x: (size.width - width * scale) / 2,
                                y: (size.height - height * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            func point(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
                CGPoint(x: x * 27 + y * 23, y: columns * 12 + shape.height + 13 - x * 12 + y * 16 - z)
            }
            func polygon(_ points: [CGPoint], shade: Color) {
                let path = Path { path in
                    path.addLines(points)
                    path.closeSubpath()
                }
                context.fill(path, with: .color(shade))
                context.stroke(path, with: .color(.black.opacity(0.16)), lineWidth: 0.65)
            }

            let backLeft = point(0, 0, shape.height)
            let backRight = point(columns, 0, shape.height)
            let frontHeight: CGFloat = shape.isSlope ? 9 : shape.height
            let frontLeft = point(0, rows, frontHeight)
            let frontRight = point(columns, rows, frontHeight)
            let leftEdge = shape.isSlope
                ? [backLeft, point(0, 1, shape.height), frontLeft, point(0, rows, 0), point(0, 0, 0)]
                : [backLeft, frontLeft, point(0, rows, 0), point(0, 0, 0)]
            polygon(leftEdge, shade: color.mix(with: .black, by: 0.18))
            polygon([frontLeft, frontRight, point(columns, rows, 0), point(0, rows, 0)], shade: color)
            if shape.isSlope {
                polygon([backLeft, backRight, point(columns, 1, shape.height), point(0, 1, shape.height)],
                        shade: color.mix(with: .white, by: 0.2))
                polygon([point(0, 1, shape.height), point(columns, 1, shape.height), frontRight, frontLeft],
                        shade: color.mix(with: .white, by: 0.1))
            } else {
                polygon([backLeft, backRight, frontRight, frontLeft], shade: color.mix(with: .white, by: 0.2))
            }

            if shape.hasStuds {
                for row in 0..<(shape.isSlope ? 1 : shape.rows) {
                    for column in (0..<shape.columns).reversed() {
                        let center = point(CGFloat(column) + 0.5, CGFloat(row) + 0.5, shape.height)
                        let bottom = CGRect(x: center.x - 9, y: center.y - 5, width: 18, height: 10)
                        let top = bottom.offsetBy(dx: 0, dy: -7)
                        let side = CGRect(x: center.x - 9, y: center.y - 7, width: 18, height: 7)
                        context.fill(Path(ellipseIn: bottom), with: .color(color.mix(with: .black, by: 0.08)))
                        context.fill(Path(side), with: .color(color))
                        context.fill(Path(ellipseIn: top), with: .color(color.mix(with: .white, by: 0.28)))
                        context.stroke(Path(ellipseIn: top), with: .color(.black.opacity(0.18)), lineWidth: 0.7)
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}

private extension Color {
    // Keep these drawings available on the app's iOS 17 deployment target.
    func mix(with other: Color, by fraction: CGFloat) -> Color {
        #if os(macOS)
        guard let first = NSColor(self).usingColorSpace(.deviceRGB),
              let second = NSColor(other).usingColorSpace(.deviceRGB) else { return self }
        #else
        let first = UIColor(self), second = UIColor(other)
        #endif
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * fraction,
                     green: g1 + (g2 - g1) * fraction,
                     blue: b1 + (b2 - b1) * fraction)
    }
}
