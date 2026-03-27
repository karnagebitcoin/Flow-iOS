import SwiftUI

struct FlowCapsuleTabBar<Selection: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding private var selection: Selection

    private let items: [Selection]
    private let title: (Selection) -> String
    @Namespace private var selectionNamespace

    init(
        selection: Binding<Selection>,
        items: [Selection],
        title: @escaping (Selection) -> String
    ) {
        _selection = selection
        self.items = items
        self.title = title
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items, id: \.self) { item in
                    tabButton(for: item)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabButton(for item: Selection) -> some View {
        let isSelected = selection == item

        return Button {
            guard selection != item else { return }
            withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                selection = item
            }
        } label: {
            Text(title(item))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSelected ? selectedForeground : unselectedForeground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(unselectedFill)

                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(selectedFill)
                                .matchedGeometryEffect(id: "selected-pill", in: selectionNamespace)
                                .shadow(
                                    color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06),
                                    radius: colorScheme == .dark ? 8 : 6,
                                    x: 0,
                                    y: 2
                                )
                        }
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(isSelected ? selectedStroke : unselectedStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var unselectedFill: Color {
        .clear
    }

    private var selectedFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.06)
    }

    private var unselectedStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.12)
    }

    private var selectedStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.2)
            : Color.black.opacity(0.14)
    }

    private var unselectedForeground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color.black.opacity(0.84)
    }

    private var selectedForeground: Color {
        colorScheme == .dark
            ? .white
            : .black
    }
}
