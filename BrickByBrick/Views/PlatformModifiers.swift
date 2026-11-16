import SwiftUI

extension View {
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// iPadOS puts an inline title on its own row under the floating tab bar, which wastes
    /// space. Keep the title for back menus and accessibility, but show it in the page.
    @ViewBuilder func compactNavigationTitle() -> some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            navigationBarTitleDisplayMode(.inline).toolbar(removing: .title)
        } else {
            navigationBarTitleDisplayMode(.inline)
        }
        #else
        self
        #endif
    }

    @ViewBuilder func hideMobileNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder func disableMobileAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder func quantityKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder func macSheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: width, minHeight: height)
        #else
        self
        #endif
    }

    @ViewBuilder func desktopFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }
}
