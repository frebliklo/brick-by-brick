import SwiftUI

struct SavedBuildCard: View {
    let build: SavedBuild

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetRow(set: build.set)
            VStack(alignment: .leading, spacing: 9) {
                ProgressView(value: build.progress).tint(Palette.green).accessibilityHidden(true)
                HStack {
                    Text("\(build.foundCount) of \(build.totalCount) pieces found")
                    Spacer()
                    if build.isComplete { Text("Ready to build") }
                    else { Text(Double(Int(build.progress * 100)) / 100, format: .percent.precision(.fractionLength(0))) }
                }.font(.caption).foregroundStyle(Palette.green)
                Label(build.foundCount == 0 ? LocalizedStringKey("Start finding bricks") : LocalizedStringKey("Continue checklist"), systemImage: "arrow.right")
                    .font(.subheadline.bold()).foregroundStyle(Palette.green).padding(.top, 6)
            }.padding(.horizontal, 18).padding(.bottom, 18)
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
