import SwiftUI
import UIKit

struct ImageRemixStaticCompositionView: View {
    let image: UIImage
    let canvasSize: CGSize
    let strokes: [ImageRemixStroke]
    let textOverlays: [ImageRemixTextOverlay]
    let stickerOverlays: [ImageRemixStickerOverlay]

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: canvasSize.width, height: canvasSize.height)

            ImageRemixDrawingLayer(
                strokes: strokes,
                activeStrokePoints: [],
                activeStrokeColor: .clear,
                activeStrokeWidth: 0,
                canvasSize: canvasSize
            )

            ForEach(textOverlays) { overlay in
                ImageRemixTextOverlayLabel(
                    overlay: overlay,
                    canvasSize: canvasSize,
                    isHighlighted: false
                )
            }

            ForEach(stickerOverlays) { overlay in
                ImageRemixStickerOverlayLabel(
                    overlay: overlay,
                    canvasSize: canvasSize,
                    isHighlighted: false
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }
}

struct ImageRemixToolButtonLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let tool: ImageRemixTool
    let isSelected: Bool
    let showsTitle: Bool
    let accentColor: Color

    var body: some View {
        VStack(spacing: showsTitle ? 6 : 0) {
            Image(systemName: tool.iconName)
                .font(.system(size: 16, weight: .semibold))

            if showsTitle {
                Text(tool.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isSelected ? .white : chromeForegroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: showsTitle ? 54 : 40)
        .background(
            RoundedRectangle(cornerRadius: showsTitle ? 18 : 16, style: .continuous)
                .fill(isSelected ? accentColor : chromeBackgroundColor)
        )
    }

    private var chromeForegroundColor: Color {
        colorScheme == .dark ? .white.opacity(0.86) : Color.black.opacity(0.84)
    }

    private var chromeBackgroundColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : Color.black.opacity(0.06)
    }
}

struct ImageRemixFilterPresetChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let preset: ImageRemixFilterPreset
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(preset.swatchGradient)
                .frame(width: 18, height: 18)

            Text(preset.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(chipForegroundColor)
                .lineLimit(1)
        }
        .frame(minHeight: 22)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? selectedFillColor : chipFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? accentColor.opacity(0.78) : chipBorderColor, lineWidth: 1)
        )
    }

    private var chipForegroundColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.9)
    }

    private var chipFillColor: Color {
        colorScheme == .dark ? .white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var selectedFillColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private var chipBorderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : Color.black.opacity(0.08)
    }
}

struct ImageRemixStickerLibraryBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let emoji: String
    var size: CGFloat = 54

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(outerFillColor)
            .overlay {
                Text(emoji)
                    .font(.system(size: size * 0.46))
                    .frame(width: size, height: size)
            }
        .frame(width: size, height: size)
    }

    private var outerFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}

struct ImageRemixDrawingLayer: View {
    let strokes: [ImageRemixStroke]
    let activeStrokePoints: [CGPoint]
    let activeStrokeColor: Color
    let activeStrokeWidth: CGFloat
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                renderStroke(
                    points: stroke.points,
                    color: stroke.palette.swiftUIColor,
                    lineWidth: stroke.lineWidth,
                    canvasSize: size,
                    in: &context
                )
            }

            renderStroke(
                points: activeStrokePoints,
                color: activeStrokeColor,
                lineWidth: activeStrokeWidth,
                canvasSize: size,
                in: &context
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func renderStroke(
        points: [CGPoint],
        color: Color,
        lineWidth: CGFloat,
        canvasSize: CGSize,
        in context: inout GraphicsContext
    ) {
        guard points.count > 1 else { return }

        var path = Path()
        let first = scaled(points[0], in: canvasSize)
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: scaled(point, in: canvasSize))
        }

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: max(min(canvasSize.width, canvasSize.height) * lineWidth, 2),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

struct ImageRemixDraggableTextOverlayView: View {
    let overlay: ImageRemixTextOverlay
    let canvasSize: CGSize
    let isHighlighted: Bool
    let allowsInteraction: Bool
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void

    @State private var dragAnchor: CGPoint?

    var body: some View {
        ImageRemixTextOverlayLabel(
            overlay: overlay,
            canvasSize: canvasSize,
            isHighlighted: isHighlighted
        )
        .allowsHitTesting(allowsInteraction)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard allowsInteraction else { return }
                    if dragAnchor == nil {
                        dragAnchor = overlay.position
                        onSelect()
                    }
                    let anchor = dragAnchor ?? overlay.position
                    onMove(
                        CGPoint(
                            x: anchor.x + (value.translation.width / canvasSize.width),
                            y: anchor.y + (value.translation.height / canvasSize.height)
                        ).clampedToUnitSquare()
                    )
                }
                .onEnded { _ in
                    dragAnchor = nil
                }
        )
        .onTapGesture {
            guard allowsInteraction else { return }
            onSelect()
        }
    }
}

struct ImageRemixDraggableStickerOverlayView: View {
    let overlay: ImageRemixStickerOverlay
    let canvasSize: CGSize
    let isHighlighted: Bool
    let allowsInteraction: Bool
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void

    @State private var dragAnchor: CGPoint?

    var body: some View {
        ImageRemixStickerOverlayLabel(
            overlay: overlay,
            canvasSize: canvasSize,
            isHighlighted: isHighlighted
        )
        .allowsHitTesting(allowsInteraction)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard allowsInteraction else { return }
                    if dragAnchor == nil {
                        dragAnchor = overlay.position
                        onSelect()
                    }
                    let anchor = dragAnchor ?? overlay.position
                    onMove(
                        CGPoint(
                            x: anchor.x + (value.translation.width / canvasSize.width),
                            y: anchor.y + (value.translation.height / canvasSize.height)
                        ).clampedToUnitSquare()
                    )
                }
                .onEnded { _ in
                    dragAnchor = nil
                }
        )
        .onTapGesture {
            guard allowsInteraction else { return }
            onSelect()
        }
    }
}

struct ImageRemixTextOverlayLabel: View {
    let overlay: ImageRemixTextOverlay
    let canvasSize: CGSize
    let isHighlighted: Bool

    var body: some View {
        if let placement = overlay.placement {
            let insets = placement.canvasInsets(for: canvasSize)
            let availableWidth = max(canvasSize.width - insets.leading - insets.trailing, 0)
            let availableHeight = max(canvasSize.height - insets.top - insets.bottom, 0)

            textLabel(multilineAlignment: placement.textAlignment)
                .frame(width: min(availableWidth, canvasSize.width * 0.76), alignment: placement.textFrameAlignment)
                .frame(width: availableWidth, height: availableHeight, alignment: placement.containerAlignment)
                .position(
                    x: insets.leading + (availableWidth / 2),
                    y: insets.top + (availableHeight / 2)
                )
        } else {
            textLabel(multilineAlignment: .center)
                .frame(maxWidth: canvasSize.width * 0.76)
                .position(x: overlay.position.x * canvasSize.width, y: overlay.position.y * canvasSize.height)
        }
    }

    private func textLabel(multilineAlignment: TextAlignment) -> some View {
        Text(overlay.text)
            .font(.system(size: max(min(canvasSize.width, canvasSize.height) * overlay.scale, 20), weight: .black, design: .rounded))
            .foregroundStyle(overlay.palette.swiftUIColor)
            .multilineTextAlignment(multilineAlignment)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isHighlighted ? .black.opacity(0.22) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isHighlighted ? .white.opacity(0.7) : .clear, style: StrokeStyle(lineWidth: 1.2, dash: [8, 6]))
            )
            .shadow(color: .black.opacity(0.42), radius: 10, x: 0, y: 6)
    }
}

struct ImageRemixStickerOverlayLabel: View {
    let overlay: ImageRemixStickerOverlay
    let canvasSize: CGSize
    let isHighlighted: Bool

    var body: some View {
        let diameter = max(min(canvasSize.width, canvasSize.height) * overlay.scale, 40)

        ZStack {
            Circle()
                .fill(isHighlighted ? .white.opacity(0.12) : .clear)

            Text(overlay.emoji)
                .font(.system(size: diameter * 0.58))
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .overlay(
            Circle()
                .stroke(isHighlighted ? .white.opacity(0.72) : .clear, style: StrokeStyle(lineWidth: 1.2, dash: [8, 6]))
        )
        .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 5)
        .position(x: overlay.position.x * canvasSize.width, y: overlay.position.y * canvasSize.height)
    }
}

struct ImageRemixPaletteStrip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let selected: ImageRemixPalette
    let onSelect: (ImageRemixPalette) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(titleColor)

            HStack(spacing: 10) {
                ForEach(ImageRemixPalette.allCases) { palette in
                    Button {
                        onSelect(palette)
                    } label: {
                        Circle()
                            .fill(palette.swiftUIColor)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(selected == palette ? selectionStrokeColor : borderColor, lineWidth: selected == palette ? 2 : 1)
                            )
                            .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : Color.black.opacity(0.62)
    }

    private var selectionStrokeColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.88)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.16) : Color.black.opacity(0.14)
    }
}

struct ImageRemixTextPlacementPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedPlacement: ImageRemixTextPlacement?
    let accentColor: Color
    let onSelect: (ImageRemixTextPlacement) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundFillColor)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderColor, lineWidth: 1)

            GeometryReader { geometry in
                ForEach(ImageRemixTextPlacement.allCases) { placement in
                    Button {
                        onSelect(placement)
                    } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selectedPlacement == placement ? accentColor : slotFillColor)
                            .frame(width: placement == .center ? 24 : 18, height: 10)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(
                                        selectedPlacement == placement ? selectedStrokeColor : Color.clear,
                                        lineWidth: 1
                                    )
                            }
                            .shadow(
                                color: selectedPlacement == placement ? accentColor.opacity(0.18) : .clear,
                                radius: 8,
                                y: 3
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(placement.title)
                    .position(
                        x: placement.previewPoint.x * geometry.size.width,
                        y: placement.previewPoint.y * geometry.size.height
                    )
                }
            }
            .padding(8)
        }
        .frame(width: 92, height: 68)
    }

    private var backgroundFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var slotFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
    }

    private var selectedStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.38)
    }
}

struct ImageRemixAccentButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
    }
}

struct ImageRemixSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(backgroundColor(configuration.isPressed))
            )
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.88)
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(isPressed ? 0.12 : 0.08)
        }
        return Color.black.opacity(isPressed ? 0.10 : 0.06)
    }
}
