import SwiftUI

enum SideMenuTransitionLayout {
    static let menuWidthFraction: CGFloat = 0.78
    static let primaryContentOpenScale: CGFloat = 0.94
    static let primaryContentOpenCornerRadius: CGFloat = 26
    static let menuTrailingCornerRadius: CGFloat = 30
    static let backdropOpacity: Double = 0.24
    static let rowStaggerDelay: TimeInterval = 0.045
    static let rowClosedYOffset: CGFloat = 10
    static let rowClosedOpacity: Double = 0
    static let profileHeaderPrimaryFillOpacity: Double = 0.08
    static let menuIconBackgroundOpacity: Double = 0.12
    static let usesParentZStack = true
    static let keepsMenuBehindPrimaryContent = true
    static let clipsCompositionToContainerBounds = true

    static func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.4, dampingFraction: 0.82)
    }

    static func menuWidth(for containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth * menuWidthFraction)
    }

    static func primaryContentOpenOffset(for containerWidth: CGFloat) -> CGFloat {
        let menuWidth = menuWidth(for: containerWidth)
        let visibleContentWidth: CGFloat = 64
        return max(0, min(menuWidth, containerWidth - visibleContentWidth))
    }
}

struct SideMenuContainer<Content: View, Menu: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding private var isOpen: Bool

    private let content: Content
    private let menu: Menu

    init(
        isOpen: Binding<Bool>,
        @ViewBuilder menu: () -> Menu,
        @ViewBuilder content: () -> Content
    ) {
        _isOpen = isOpen
        self.menu = menu()
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let menuWidth = SideMenuTransitionLayout.menuWidth(for: geometry.size.width)
            let contentOffset = SideMenuTransitionLayout.primaryContentOpenOffset(
                for: geometry.size.width
            )

            ZStack(alignment: .leading) {
                menuLayer(width: menuWidth)
                    .zIndex(0)

                primaryContentLayer(offset: contentOffset)
                    .zIndex(1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .animation(
                SideMenuTransitionLayout.animation(reduceMotion: accessibilityReduceMotion),
                value: isOpen
            )
        }
    }

    private func menuLayer(width: CGFloat) -> some View {
        menu
            .environment(\.sideMenuPresentationIsOpen, isOpen)
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .clipShape(SideMenuTrailingRoundedShape(radius: SideMenuTransitionLayout.menuTrailingCornerRadius))
            .contentShape(SideMenuTrailingRoundedShape(radius: SideMenuTransitionLayout.menuTrailingCornerRadius))
            .shadow(color: .black.opacity(isOpen ? 0.18 : 0), radius: isOpen ? 22 : 0, x: 10, y: 16)
            .offset(x: isOpen ? 0 : -width * 0.42)
            .opacity(isOpen ? 1 : 0.82)
            .allowsHitTesting(isOpen)
            .accessibilityHidden(!isOpen)
    }

    private func primaryContentLayer(offset: CGFloat) -> some View {
        content
            .disabled(isOpen)
            .scaleEffect(
                isOpen ? SideMenuTransitionLayout.primaryContentOpenScale : 1,
                anchor: .center
            )
            .offset(x: isOpen ? offset : 0)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: isOpen ? SideMenuTransitionLayout.primaryContentOpenCornerRadius : 0,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(isOpen ? 0.22 : 0), radius: isOpen ? 20 : 0, x: -8, y: 14)
            .overlay {
                if isOpen {
                    Button {
                        closeMenu()
                    } label: {
                        Rectangle()
                            .fill(Color.black.opacity(SideMenuTransitionLayout.backdropOpacity))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss side menu")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                }
            }
    }

    private func closeMenu() {
        if let animation = SideMenuTransitionLayout.animation(reduceMotion: accessibilityReduceMotion) {
            withAnimation(animation) {
                isOpen = false
            }
        } else {
            isOpen = false
        }
    }
}

private struct SideMenuTrailingRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let clippedRadius = max(0, min(radius, rect.width / 2, rect.height / 2))
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - clippedRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + clippedRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - clippedRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - clippedRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct SideMenuPresentationIsOpenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sideMenuPresentationIsOpen: Bool {
        get { self[SideMenuPresentationIsOpenKey.self] }
        set { self[SideMenuPresentationIsOpenKey.self] = newValue }
    }
}
