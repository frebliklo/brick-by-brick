import SwiftUI

extension View {
    /// Keep controls readable on iPad while filling narrower multitasking windows.
    func pageWidth(_ maximum: CGFloat = 1040) -> some View {
        frame(maxWidth: maximum).frame(maxWidth: .infinity, alignment: .top)
    }
}

struct AdaptiveCardGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var availableWidth: CGFloat = 0
    @State private var animatesColumns = false
    var minimumCardWidth: CGFloat = 360
    var maximumColumns: Int = .max
    @ViewBuilder let content: Content

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : min(maximumColumns, max(1, Int((availableWidth + 16) / (minimumCardWidth + 16))))
        return Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) { content }
            // Only re-flow with animation when the window changes size, never on first layout.
            .animation(animatesColumns ? .smooth(duration: 0.3) : nil, value: columns.count)
            // Hide the single unmeasured frame so cards don't visibly jump into columns.
            .opacity(availableWidth > 0 ? 1 : 0)
            .background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in
                        availableWidth = width
                        if width > 0, !animatesColumns {
                            DispatchQueue.main.async { animatesColumns = true }
                        }
                    }
                }
            }
    }
}

/// Warm, toy-box colors that adapt to light and dark appearances.
enum Palette {
    static let background = Color(light: "F7F5F0", dark: "171918")
    static let surface = Color(light: "FFFFFF", dark: "232726")
    static let ink = Color(light: "242D32", dark: "F0EFEA")
    static let muted = Color(light: "69726E", dark: "A3AAA6")
    static let orange = Color(light: "C34C2C", dark: "DE6440")
    static let orangeTint = Color(light: "FBEBE4", dark: "3B2721")
    static let green = Color(light: "35674E", dark: "4C8E6A")
    static let greenTint = Color(light: "EEF2E9", dark: "1E2C24")
    static let line = Color(light: "E5E5DC", dark: "363B39")
    static let scene = Color(light: "EAE8DA", dark: "262A28")
    static let shadow = Color.black
}

extension Color {
    init(hex: String) {
        let number = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xAAAAAA
        self.init(.sRGB, red: Double((number >> 16) & 255) / 255,
                  green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255, opacity: 1)
    }

    init(light: String, dark: String) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(Color(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light))
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #endif
    }
}

extension View {
    /// A light tile for part and set photos. White photo backgrounds melt into the tile.
    func imageWell(cornerRadius: CGFloat) -> some View { modifier(ImageWell(cornerRadius: cornerRadius)) }
}

private struct ImageWell: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, .light)
            .background(scheme == .dark ? Color(hex: "E6E3DA") : Color(hex: "F7F5F0"))
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct Eyebrow: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).textCase(.uppercase).font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(2).foregroundStyle(Palette.muted)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.white).background(Palette.orange, in: RoundedRectangle(cornerRadius: 17))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct BrickDrawing: View {
    var color: Color = Palette.orange
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.08).fill(color.gradient)
                    .frame(width: w * 0.9, height: h * 0.64).offset(y: h * 0.12)
                RoundedRectangle(cornerRadius: w * 0.06).fill(color.opacity(0.75))
                    .frame(width: w * 0.9, height: h * 0.38).offset(y: -h * 0.03)
                ForEach(0..<2) { row in
                    ForEach(0..<3) { col in
                        Ellipse().fill(color.gradient)
                            .overlay(Ellipse().strokeBorder(.white.opacity(0.28), lineWidth: 1.5))
                            .frame(width: w * 0.21, height: h * 0.20)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 3)
                            .offset(x: CGFloat(col - 1) * w * 0.28, y: CGFloat(row) * h * 0.23 - h * 0.21)
                    }
                }
            }.frame(width: w, height: h)
        }.accessibilityHidden(true)
    }
}

struct BrickScene: View {
    var body: some View {
        ZStack {
            Circle().fill(Palette.scene).frame(width: 190, height: 190)
            BrickDrawing(color: Color(hex: "E9B838")).frame(width: 124, height: 88)
                .rotationEffect(.degrees(-14)).offset(x: -45, y: 32)
            BrickDrawing(color: Color(hex: "3F705B")).frame(width: 105, height: 74)
                .rotationEffect(.degrees(14)).offset(x: 62, y: 28)
            BrickDrawing(color: Color(hex: "D86646")).frame(width: 128, height: 90)
                .rotationEffect(.degrees(-7)).offset(x: -4, y: -36)
        }.frame(height: 220).accessibilityHidden(true)
    }
}

struct CatalogImage: View {
    let url: URL?
    var color: Color = Palette.orange
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().blendMode(.multiply).padding(6)
            } else {
                BrickDrawing(color: color).padding(18)
            }
        }.accessibilityHidden(true)
    }
}

struct SetRow: View {
    let set: LEGOSet
    var saved = false
    /// Off where the row isn't a navigation link.
    var showsChevron = true
    var body: some View {
        HStack(spacing: 15) {
            CatalogImage(url: set.setImgUrl).frame(width: 84, height: 80)
                .imageWell(cornerRadius: 14)
            VStack(alignment: .leading, spacing: 6) {
                Text(set.isSample ? LocalizedStringKey("PRACTICE SET") : LocalizedStringKey("SET \(set.setNum)"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
                Text(set.name).font(.headline).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                Text("\(set.numParts) pieces · \(String(set.year))").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            if saved || showsChevron {
                Image(systemName: saved ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(saved ? Palette.green : Palette.muted).font(.subheadline)
            }
        }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct InlineMessage: View {
    let text: Text
    var body: some View {
        Label { text } icon: { Image(systemName: "info.circle") }.font(.subheadline).foregroundStyle(Palette.muted)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
