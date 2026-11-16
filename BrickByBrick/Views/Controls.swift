import SwiftUI

/// A soft, rounded search field without the platform bezel or focus ring.
struct SoftSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var large = false
    var identifier: String
    var clearLabel: LocalizedStringKey
    /// Sit the field into a surrounding card instead of floating above the page.
    var recessed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: large ? 12 : 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: large ? 17 : 14, weight: .bold))
                .foregroundStyle(focused ? Color.white : Palette.orange)
                .frame(width: large ? 40 : 32, height: large ? 40 : 32)
                .background(focused ? Palette.orange : Palette.orangeTint, in: Circle())
                .contentShape(Circle())
                .onTapGesture { focused = true }
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(large ? .title3 : .body, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.ink)
                .focused($focused)
                .focusEffectDisabled()
                .autocorrectionDisabled().disableMobileAutocapitalization()
                .submitLabel(.search)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = ""; focused = true } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 26, height: 26).background(Palette.line, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(clearLabel)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.leading, large ? 10 : 8).padding(.trailing, text.isEmpty ? 16 : 4)
        .frame(minHeight: large ? 62 : 52)
        .background(recessed ? Palette.background : Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Palette.orange.opacity(0.6) : Palette.line, lineWidth: focused ? 2 : 1))
        .shadow(color: Palette.shadow.opacity(recessed ? 0 : focused ? 0.12 : 0.05), radius: focused ? 14 : 6, y: focused ? 6 : 2)
        .animation(.snappy(duration: 0.22), value: focused)
        .animation(.snappy(duration: 0.22), value: text.isEmpty)
    }
}

/// Lays children out left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width = needed
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows
    }
}

/// A chunky, tappable choice for kids: icon plus word, filled when selected.
struct ChoiceChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(selected ? Color.white : Palette.ink)
                .background(selected ? Palette.orange : Palette.background, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : Palette.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Brick-stud swatches: pick a color by seeing it, not by reading a list.
struct ColorSwatchPicker: View {
    let colors: [BrickColor]
    @Binding var selection: Int?

    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 10) {
            Swatch(fill: AnyShapeStyle(AngularGradient(colors: rainbow, center: .center)),
                   checkColor: .white, selected: selection == nil) { selection = nil }
                .accessibilityLabel("All colors")
                .help(Text("All colors"))
            ForEach(colors, id: \.id) { color in
                Swatch(fill: AnyShapeStyle(Color(hex: color.rgb)),
                       checkColor: Self.isLight(color.rgb) ? .black : .white,
                       selected: selection == color.id) { selection = selection == color.id ? nil : color.id }
                    .accessibilityLabel(Text(verbatim: color.name))
                    .help(Text(verbatim: color.name))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by color")
    }

    private var rainbow: [Color] {
        ["D9523B", "F4BE37", "6BAF5B", "4D8FCC", "8E5BB5", "D9523B"].map { Color(hex: $0) }
    }

    static func isLight(_ hex: String) -> Bool {
        let n = UInt64(hex, radix: 16) ?? 0
        let r = Double((n >> 16) & 255), g = Double((n >> 8) & 255), b = Double(n & 255)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 165
    }

    private struct Swatch: View {
        let fill: AnyShapeStyle
        let checkColor: Color
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    Circle().fill(fill)
                    // A stud on top, so each swatch reads as a little brick.
                    Circle().fill(.white.opacity(0.16)).padding(9)
                    Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1.5).padding(9)
                    Circle().strokeBorder(.black.opacity(0.14), lineWidth: 1)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .black))
                            .foregroundStyle(checkColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 40, height: 40)
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? Palette.ink : .clear, lineWidth: 2.5))
                .scaleEffect(selected ? 1.06 : 1)
                .contentShape(Circle())
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selected)
            }
            .buttonStyle(PressableStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// Plain buttons that squish a little when pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
