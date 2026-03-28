import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import SwiftUI
import UIKit

struct ImageRemixEditorView: View {
    let baseImage: UIImage
    let sourceEvent: NostrEvent
    let currentAccountPubkey: String?
    let currentNsec: String?
    let writeRelayURLs: [URL]
    let onComposeRequested: (ComposeMediaAttachment, NostrEvent?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastCenter: AppToastCenter
    @EnvironmentObject private var appSettings: AppSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var filteredPreviewImage: UIImage
    @State private var selectedTool: ImageRemixTool?
    @State private var selectedFilter: ImageRemixFilterPreset = .original
    @State private var previewRequestID = UUID()
    @State private var isPreparingFilter = false
    @State private var strokes: [ImageRemixStroke] = []
    @State private var activeStrokePoints: [CGPoint] = []
    @State private var textOverlays: [ImageRemixTextOverlay] = []
    @State private var stickerOverlays: [ImageRemixStickerOverlay] = []
    @State private var selectedOverlayID: UUID?
    @State private var draftText = ""
    @State private var stickerSearchQuery = ""
    @State private var draftTextPalette: ImageRemixPalette = .sunlight
    @State private var draftTextPlacement: ImageRemixTextPlacement = .center
    @State private var draftStickerScale: CGFloat = 0.15
    @State private var draftTextScale: CGFloat = 0.09
    @State private var draftBrushPalette: ImageRemixPalette = .polar
    @State private var draftBrushWidth: CGFloat = 0.012
    @State private var redoStrokes: [ImageRemixStroke] = []
    @State private var isToolPanelExpanded = false
    @State private var isSavingImage = false
    @State private var isUploadingImage = false
    @State private var isShowingPostOptions = false
    @State private var confirmationBannerMessage: String?
    @State private var confirmationBannerRequestID = UUID()

    private let mediaUploadService = MediaUploadService.shared

    init(
        sourceImage: UIImage,
        sourceEvent: NostrEvent,
        currentAccountPubkey: String?,
        currentNsec: String?,
        writeRelayURLs: [URL],
        onComposeRequested: @escaping (ComposeMediaAttachment, NostrEvent?) -> Void
    ) {
        let preparedImage = sourceImage.flowPreparedForRemix(maxDimension: 1_800)
        self.baseImage = preparedImage
        self.sourceEvent = sourceEvent
        self.currentAccountPubkey = currentAccountPubkey
        self.currentNsec = currentNsec
        self.writeRelayURLs = writeRelayURLs
        self.onComposeRequested = onComposeRequested
        _filteredPreviewImage = State(initialValue: preparedImage)
    }

    var body: some View {
        ZStack {
            remixBackground

            if isShowingPostOptions {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                            isShowingPostOptions = false
                        }
                    }
            }

            VStack(spacing: 0) {
                topBar

                GeometryReader { geometry in
                    let canvasSize = fittedCanvasSize(in: geometry.size)

                    VStack {
                        Spacer(minLength: 0)

                        editorCanvas(canvasSize: canvasSize)
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .background(
                                editorBackgroundColor,
                                in: RoundedRectangle(cornerRadius: 34, style: .continuous)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(canvasBorderColor, lineWidth: 1)
                            )
                            .offset(y: canvasVerticalOffset)
                            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isToolPanelExpanded)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
            }

            if isPreparingFilter || isSavingImage || isUploadingImage {
                processingOverlay
            }

            if let confirmationBannerMessage {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text(confirmationBannerMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.top, 86)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .bottom) {
            bottomToolPanel
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
        }
        .onChange(of: selectedFilter) { _, _ in
            refreshFilteredPreview()
        }
    }

    private var remixBackground: some View {
        Rectangle()
            .fill(editorBackgroundColor)
            .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(chromePrimaryColor)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close editor")

            VStack(alignment: .leading, spacing: 2) {
                Text("Remix")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(chromePrimaryColor)

                Text(selectedFilter == .original ? "Add some chaos" : selectedFilter.title)
                    .font(.footnote)
                    .foregroundStyle(chromeSecondaryColor)
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    await saveEditedImageToLibrary()
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(chromePrimaryColor)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("Save edited image")

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isShowingPostOptions.toggle()
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(appSettings.primaryColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.65 : 1)
            .accessibilityLabel("Post remix")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .overlay(alignment: .topTrailing) {
            if isShowingPostOptions {
                postOptionsDropdown
                    .padding(.trailing, 16)
                    .offset(y: 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .zIndex(1)
    }

    private var postOptionsDropdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                beginPostFlow(forReply: false)
            } label: {
                postOptionRow(
                    title: "Post as new note",
                    subtitle: "Open composer with your remix attached",
                    systemImage: "square.and.pencil"
                )
            }
            .buttonStyle(.plain)

            Button {
                beginPostFlow(forReply: true)
            } label: {
                postOptionRow(
                    title: "Reply with remix",
                    subtitle: "Attach it to a reply composer",
                    systemImage: "arrowshape.turn.up.left"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(postOptionsBackgroundColor)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(controlBorderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)
    }

    private func postOptionRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(appSettings.primaryColor.opacity(0.88), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chromePrimaryColor)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(chromeSecondaryColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 234, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(controlRowFillColor)
        )
    }

    private var bottomToolPanel: some View {
        VStack(alignment: .leading, spacing: isToolPanelExpanded ? 16 : 0) {
            HStack(spacing: 10) {
                ForEach(ImageRemixTool.allCases) { tool in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                            selectedTool = tool
                            isToolPanelExpanded = true
                        }
                    } label: {
                        ImageRemixToolButtonLabel(
                            tool: tool,
                            isSelected: selectedTool == tool,
                            showsTitle: isToolPanelExpanded,
                            accentColor: appSettings.primaryColor
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        isToolPanelExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isToolPanelExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(chromePrimaryColor)
                        .frame(width: 40, height: 40)
                        .background(controlFillColor, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isToolPanelExpanded ? "Minimize tools" : "Expand tools")
            }

            if isToolPanelExpanded {
                Group {
                    if let selectedTool {
                        switch selectedTool {
                        case .filters:
                            filtersPanel
                        case .draw:
                            drawPanel
                        case .text:
                            textPanel
                        case .stickers:
                            stickersPanel
                        }
                    } else {
                        toolSelectionPrompt
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(toolPanelTint)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(toolPanelBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var filtersPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fun Filters")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(chromePrimaryColor)

            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(ImageRemixFilterPreset.allCases) { preset in
                            Button {
                                selectedFilter = preset
                            } label: {
                                ImageRemixFilterPresetChip(
                                    preset: preset,
                                    isSelected: selectedFilter == preset,
                                    accentColor: appSettings.primaryColor
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 58)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, edgeFadeColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 34)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(chromeTertiaryColor)
                        .padding(.trailing, 4)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var drawPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Brush")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chromePrimaryColor)

                Spacer(minLength: 0)

                Text("Draw right on the image")
                    .font(.caption)
                    .foregroundStyle(chromeSecondaryColor)
            }

            ImageRemixPaletteStrip(
                title: "Color",
                selected: draftBrushPalette,
                onSelect: { draftBrushPalette = $0 }
            )

            HStack(spacing: 12) {
                Text("Width")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(chromeMutedColor)
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(draftBrushWidth) },
                        set: { draftBrushWidth = CGFloat($0) }
                    ),
                    in: 0.005...0.028
                )
                .tint(appSettings.primaryColor)
            }

            HStack(spacing: 10) {
                Button {
                    undoLastStroke()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(ImageRemixSecondaryButtonStyle())
                .disabled(strokes.isEmpty)

                Button {
                    redoLastStroke()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .buttonStyle(ImageRemixSecondaryButtonStyle())
                .disabled(redoStrokes.isEmpty)

                Button {
                    strokes.removeAll()
                    redoStrokes.removeAll()
                    activeStrokePoints.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(ImageRemixSecondaryButtonStyle())
                .disabled(strokes.isEmpty && activeStrokePoints.isEmpty)
            }
        }
    }

    private var textPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Text")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chromePrimaryColor)

                Spacer(minLength: 0)

                Text(selectedTextOverlay == nil ? "Type and drop it in" : "Drag it or snap it below")
                    .font(.caption)
                    .foregroundStyle(chromeSecondaryColor)
            }

            HStack(spacing: 10) {
                TextField("Write something loud", text: $draftText)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(controlFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(chromePrimaryColor)

                Button("Add") {
                    addTextOverlay()
                }
                .buttonStyle(ImageRemixAccentButtonStyle(color: appSettings.primaryColor))
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ImageRemixPaletteStrip(
                title: "Color",
                selected: activeTextPalette,
                onSelect: { palette in
                    if let selectedID = selectedTextOverlay?.id {
                        updateTextOverlay(id: selectedID) { overlay in
                            overlay.palette = palette
                        }
                    } else {
                        draftTextPalette = palette
                    }
                }
            )

            HStack(spacing: 12) {
                Text("Size")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(chromeMutedColor)
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(activeTextScale) },
                        set: { newValue in
                            if let selectedID = selectedTextOverlay?.id {
                                updateTextOverlay(id: selectedID) { overlay in
                                    overlay.scale = CGFloat(newValue)
                                }
                            } else {
                                draftTextScale = CGFloat(newValue)
                            }
                        }
                    ),
                    in: 0.055...0.16
                )
                .tint(appSettings.primaryColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Position")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(chromeMutedColor)

                    Spacer(minLength: 0)

                    Text(activeTextPlacement?.title ?? "Custom")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(chromePrimaryColor.opacity(0.82))
                }

                HStack(alignment: .bottom, spacing: 12) {
                    ImageRemixTextPlacementPicker(
                        selectedPlacement: activeTextPlacement,
                        accentColor: appSettings.primaryColor,
                        onSelect: applyTextPlacement(_:)
                    )

                    if let selectedTextOverlay {
                        Button("Delete", role: .destructive) {
                            textOverlays.removeAll { $0.id == selectedTextOverlay.id }
                            selectedOverlayID = nil
                        }
                        .buttonStyle(ImageRemixSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var stickersPanel: some View {
        let stickerResults = filteredStickerEntries
        let stickerGridColumns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: 42), spacing: 8), count: 7)
        let hasTypedEmojiCandidate = typedStickerCandidate != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Emoji Stickers")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chromePrimaryColor)

                Spacer(minLength: 0)

                Text(normalizedStickerSearchQuery.isEmpty ? "Search, type, or tap to drop" : "\(stickerResults.count) result\(stickerResults.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(chromeSecondaryColor)
            }

            if normalizedStickerSearchQuery.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Picks")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(chromeMutedColor)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ImageRemixEmojiEntry.featured) { entry in
                                Button {
                                    selectStickerFromPicker(entry.emoji)
                                } label: {
                                    ImageRemixStickerLibraryBadge(emoji: entry.emoji, size: 42)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 42)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chromeTertiaryColor)

                TextField("Search emoji or keyword", text: $stickerSearchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(chromePrimaryColor)

                if !stickerSearchQuery.isEmpty {
                    Button {
                        stickerSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(chromeTertiaryColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear emoji search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(controlFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let typedStickerCandidate {
                Button {
                    selectStickerFromPicker(typedStickerCandidate)
                } label: {
                    HStack(spacing: 10) {
                        ImageRemixStickerLibraryBadge(emoji: typedStickerCandidate, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use typed emoji")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(chromePrimaryColor)

                            Text(typedStickerCandidate)
                                .font(.caption)
                                .foregroundStyle(chromeSecondaryColor)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(appSettings.primaryColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(controlRowFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if stickerResults.isEmpty {
                Text("No emoji match that search yet.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(chromeSecondaryColor)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: stickerGridColumns, spacing: 8) {
                        ForEach(stickerResults) { entry in
                            Button {
                                selectStickerFromPicker(entry.emoji)
                            } label: {
                                ImageRemixStickerLibraryBadge(emoji: entry.emoji, size: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: hasTypedEmojiCandidate ? 138 : 154)
            }

            HStack(spacing: 12) {
                Text("Size")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(chromeMutedColor)
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(activeStickerScale) },
                        set: { newValue in
                            if let selectedID = selectedStickerOverlay?.id {
                                updateStickerOverlay(id: selectedID) { overlay in
                                    overlay.scale = CGFloat(newValue)
                                }
                            } else {
                                draftStickerScale = CGFloat(newValue)
                            }
                        }
                    ),
                    in: 0.08...0.24
                )
                .tint(appSettings.primaryColor)
            }

            if let selectedStickerOverlay {
                HStack(spacing: 10) {
                    Button("Center") {
                        updateStickerOverlay(id: selectedStickerOverlay.id) { overlay in
                            overlay.position = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
                    .buttonStyle(ImageRemixSecondaryButtonStyle())

                    Button("Delete", role: .destructive) {
                        stickerOverlays.removeAll { $0.id == selectedStickerOverlay.id }
                        selectedOverlayID = nil
                    }
                    .buttonStyle(ImageRemixSecondaryButtonStyle())
                }
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(chromePrimaryColor)

                Text(progressTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chromePrimaryColor)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var toolSelectionPrompt: some View {
        Text("Pick a tool to start editing.")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(chromeSecondaryColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func editorCanvas(canvasSize: CGSize) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedOverlayID = nil
                }

            Image(uiImage: filteredPreviewImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: canvasSize.width, height: canvasSize.height)

            ImageRemixDrawingLayer(
                strokes: strokes,
                activeStrokePoints: activeStrokePoints,
                activeStrokeColor: draftBrushPalette.swiftUIColor,
                activeStrokeWidth: draftBrushWidth,
                canvasSize: canvasSize
            )

            ForEach(textOverlays) { overlay in
                ImageRemixDraggableTextOverlayView(
                    overlay: overlay,
                    canvasSize: canvasSize,
                    isHighlighted: overlay.id == selectedOverlayID && selectedTool != .draw,
                    allowsInteraction: selectedTool != .draw,
                    onSelect: {
                        selectedOverlayID = overlay.id
                        selectedTool = .text
                        isToolPanelExpanded = true
                    },
                    onMove: { normalizedPosition in
                        updateTextOverlay(id: overlay.id) { mutableOverlay in
                            mutableOverlay.placement = nil
                            mutableOverlay.position = normalizedPosition
                        }
                    }
                )
            }

            ForEach(stickerOverlays) { overlay in
                ImageRemixDraggableStickerOverlayView(
                    overlay: overlay,
                    canvasSize: canvasSize,
                    isHighlighted: overlay.id == selectedOverlayID && selectedTool != .draw,
                    allowsInteraction: selectedTool != .draw,
                    onSelect: {
                        selectedOverlayID = overlay.id
                        selectedTool = .stickers
                        isToolPanelExpanded = true
                    },
                    onMove: { normalizedPosition in
                        updateStickerOverlay(id: overlay.id) { mutableOverlay in
                            mutableOverlay.position = normalizedPosition
                        }
                    }
                )
            }

            if selectedTool == .draw {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let normalizedPoint = CGPoint(
                                    x: (value.location.x / canvasSize.width).clamped(to: 0...1),
                                    y: (value.location.y / canvasSize.height).clamped(to: 0...1)
                                )
                                activeStrokePoints.append(normalizedPoint)
                            }
                            .onEnded { _ in
                                guard activeStrokePoints.count > 1 else {
                                    activeStrokePoints.removeAll()
                                    return
                                }

                                strokes.append(
                                    ImageRemixStroke(
                                        points: activeStrokePoints,
                                        palette: draftBrushPalette,
                                        lineWidth: draftBrushWidth
                                    )
                                )
                                redoStrokes.removeAll()
                                activeStrokePoints.removeAll()
                            }
                    )
            }
        }
    }

    private var isBusy: Bool {
        isPreparingFilter || isSavingImage || isUploadingImage
    }

    private var canvasVerticalOffset: CGFloat {
        isToolPanelExpanded ? -24 : 0
    }

    private var editorBackgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var canvasBorderColor: Color {
        colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.06)
    }

    private var chromePrimaryColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.92)
    }

    private var chromeSecondaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color.black.opacity(0.68)
    }

    private var chromeMutedColor: Color {
        colorScheme == .dark ? .white.opacity(0.70) : Color.black.opacity(0.62)
    }

    private var chromeTertiaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.56) : Color.black.opacity(0.48)
    }

    private var controlFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var controlRowFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
    }

    private var controlBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private var edgeFadeColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.55)
    }

    private var postOptionsBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.94)
            : Color(.systemBackground).opacity(0.94)
    }

    private var toolPanelTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.34) : Color.white.opacity(0.28)
    }

    private var toolPanelBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private var progressTitle: String {
        if isUploadingImage {
            return "Uploading your remix..."
        }
        if isSavingImage {
            return "Saving to Photos..."
        }
        return "Applying \(selectedFilter.title)..."
    }

    private var selectedTextOverlay: ImageRemixTextOverlay? {
        guard let selectedOverlayID else { return nil }
        return textOverlays.first(where: { $0.id == selectedOverlayID })
    }

    private var selectedStickerOverlay: ImageRemixStickerOverlay? {
        guard let selectedOverlayID else { return nil }
        return stickerOverlays.first(where: { $0.id == selectedOverlayID })
    }

    private var activeTextPalette: ImageRemixPalette {
        selectedTextOverlay?.palette ?? draftTextPalette
    }

    private var activeTextScale: CGFloat {
        selectedTextOverlay?.scale ?? draftTextScale
    }

    private var activeTextPlacement: ImageRemixTextPlacement? {
        if let selectedTextOverlay {
            return selectedTextOverlay.placement
        }
        return draftTextPlacement
    }

    private var activeStickerScale: CGFloat {
        selectedStickerOverlay?.scale ?? draftStickerScale
    }

    private var normalizedStickerSearchQuery: String {
        stickerSearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var typedStickerCandidate: String? {
        normalizedStickerSearchQuery.firstEmojiCluster
    }

    private var filteredStickerEntries: [ImageRemixEmojiEntry] {
        guard !normalizedStickerSearchQuery.isEmpty else {
            return ImageRemixEmojiEntry.catalog
        }

        let queryTerms = normalizedStickerSearchQuery.split(whereSeparator: \.isWhitespace)
        return ImageRemixEmojiEntry.catalog.filter { entry in
            queryTerms.allSatisfy { entry.matches(searchTerm: String($0)) }
        }
    }

    private func fittedCanvasSize(in availableSize: CGSize) -> CGSize {
        guard baseImage.size.width > 0, baseImage.size.height > 0 else {
            return CGSize(width: max(availableSize.width - 40, 0), height: max(availableSize.height - 40, 0))
        }

        let maxWidth = max(availableSize.width - 40, 120)
        let maxHeight = max(availableSize.height - 40, 120)
        let widthRatio = maxWidth / baseImage.size.width
        let heightRatio = maxHeight / baseImage.size.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(
            width: baseImage.size.width * scale,
            height: baseImage.size.height * scale
        )
    }

    private func refreshFilteredPreview() {
        previewRequestID = UUID()
        let requestID = previewRequestID
        let preset = selectedFilter
        let source = baseImage

        if preset == .original {
            filteredPreviewImage = source
            isPreparingFilter = false
            return
        }

        isPreparingFilter = true
        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = ImageRemixFilterProcessor.renderedImage(for: preset, from: source)
            DispatchQueue.main.async {
                guard previewRequestID == requestID else { return }
                filteredPreviewImage = rendered
                isPreparingFilter = false
            }
        }
    }

    private func addTextOverlay() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let overlay = ImageRemixTextOverlay(
            text: trimmed,
            palette: draftTextPalette,
            scale: draftTextScale,
            position: draftTextPlacement.normalizedAnchorPoint,
            placement: draftTextPlacement
        )
        textOverlays.append(overlay)
        selectedOverlayID = overlay.id
        draftText = ""
    }

    private func addStickerOverlay(emoji: String) {
        let offset = min(CGFloat(stickerOverlays.count), 4) * 0.05
        let overlay = ImageRemixStickerOverlay(
            emoji: emoji,
            scale: draftStickerScale,
            position: CGPoint(
                x: (0.5 - offset).clamped(to: 0.16...0.84),
                y: (0.5 + offset * 0.35).clamped(to: 0.2...0.8)
            )
        )
        stickerOverlays.append(overlay)
        selectedOverlayID = overlay.id
    }

    private func selectStickerFromPicker(_ emoji: String) {
        addStickerOverlay(emoji: emoji)
        stickerSearchQuery = ""
    }

    private func undoLastStroke() {
        guard let removedStroke = strokes.popLast() else { return }
        redoStrokes.append(removedStroke)
    }

    private func redoLastStroke() {
        guard let restoredStroke = redoStrokes.popLast() else { return }
        strokes.append(restoredStroke)
    }

    private func updateTextOverlay(id: UUID, mutate: (inout ImageRemixTextOverlay) -> Void) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        var overlay = textOverlays[index]
        mutate(&overlay)
        overlay.position = overlay.position.clampedToUnitSquare()
        textOverlays[index] = overlay
    }

    private func applyTextPlacement(_ placement: ImageRemixTextPlacement) {
        if let selectedID = selectedTextOverlay?.id {
            updateTextOverlay(id: selectedID) { overlay in
                overlay.placement = placement
                overlay.position = placement.normalizedAnchorPoint
            }
        } else {
            draftTextPlacement = placement
        }
    }

    private func updateStickerOverlay(id: UUID, mutate: (inout ImageRemixStickerOverlay) -> Void) {
        guard let index = stickerOverlays.firstIndex(where: { $0.id == id }) else { return }
        var overlay = stickerOverlays[index]
        mutate(&overlay)
        overlay.position = overlay.position.clampedToUnitSquare()
        stickerOverlays[index] = overlay
    }

    private func renderEditedImage() -> UIImage {
        let filteredImage = ImageRemixFilterProcessor.renderedImage(for: selectedFilter, from: baseImage)
        let content = ImageRemixStaticCompositionView(
            image: filteredImage,
            canvasSize: filteredImage.size,
            strokes: strokes,
            textOverlays: textOverlays,
            stickerOverlays: stickerOverlays
        )

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(filteredImage.size)
        return renderer.uiImage ?? filteredImage
    }

    private func saveEditedImageToLibrary() async {
        guard !isBusy else { return }
        isSavingImage = true
        let image = renderEditedImage()

        let authorizationStatus = await ImageRemixPhotoLibrary.requestWriteAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            isSavingImage = false
            toastCenter.show("Photos access is needed to save.", style: .error, duration: 2.8)
            return
        }

        do {
            try await ImageRemixPhotoLibrary.save(image: image)
            isSavingImage = false
            toastCenter.show("Saved")
            showConfirmationBanner("Saved to Photos")
        } catch {
            isSavingImage = false
            toastCenter.show(
                (error as? LocalizedError)?.errorDescription ?? "Couldn't save that image right now.",
                style: .error,
                duration: 2.8
            )
        }
    }

    private func uploadEditedImage(forReply: Bool) async {
        guard !isBusy else { return }

        guard let normalizedNsec = currentNsec?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedNsec.isEmpty else {
            toastCenter.show("Sign in with a private key to post remixes.", style: .error, duration: 2.8)
            return
        }

        guard !writeRelayURLs.isEmpty else {
            toastCenter.show("Add a publish source before posting.", style: .error, duration: 2.8)
            return
        }

        let image = renderEditedImage()
        guard let imageData = image.jpegData(compressionQuality: 0.94) else {
            toastCenter.show("Couldn't prepare that image for upload.", style: .error, duration: 2.8)
            return
        }

        isUploadingImage = true
        defer {
            isUploadingImage = false
        }

        do {
            let result = try await mediaUploadService.uploadMedia(
                data: imageData,
                mimeType: "image/jpeg",
                filename: "remix-\(UUID().uuidString).jpg",
                nsec: normalizedNsec,
                provider: appSettings.mediaUploadProvider
            )

            onComposeRequested(
                ComposeMediaAttachment(
                    url: result.url,
                    imetaTag: result.imetaTag,
                    mimeType: "image/jpeg",
                    fileSizeBytes: imageData.count
                ),
                forReply ? sourceEvent : nil
            )
        } catch {
            toastCenter.show(
                (error as? LocalizedError)?.errorDescription ?? "Couldn't upload that remixed image right now.",
                style: .error,
                duration: 2.8
            )
        }
    }

    private func beginPostFlow(forReply: Bool) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            isShowingPostOptions = false
        }

        Task {
            await uploadEditedImage(forReply: forReply)
        }
    }

    private func showConfirmationBanner(_ message: String) {
        let requestID = UUID()
        confirmationBannerRequestID = requestID
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            confirmationBannerMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            guard confirmationBannerRequestID == requestID else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                confirmationBannerMessage = nil
            }
        }
    }
}

private enum ImageRemixTool: String, CaseIterable, Identifiable {
    case filters
    case draw
    case text
    case stickers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filters:
            return "Filters"
        case .draw:
            return "Draw"
        case .text:
            return "Text"
        case .stickers:
            return "Stickers"
        }
    }

    var iconName: String {
        switch self {
        case .filters:
            return "sparkles"
        case .draw:
            return "scribble.variable"
        case .text:
            return "textformat"
        case .stickers:
            return "face.smiling"
        }
    }
}

private enum ImageRemixFilterPreset: String, CaseIterable, Identifiable {
    case original
    case duotoneGradient
    case tritoneEditorial
    case metallicChrome
    case liquidMetalFlow
    case hologram
    case prismDispersion
    case softBloomGlow
    case neonGlow
    case glassFrostedBlur
    case lightSweep
    case filmGrainCinematic
    case vintageFilmFade
    case vhs90sTape
    case crtScanline
    case halftonePrint
    case posterizeQuantize
    case glitchClean
    case chromaticAberration
    case thermalHeatmap
    case pixelSortDataMelt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "Original"
        case .duotoneGradient:
            return "Duotone Gradient"
        case .tritoneEditorial:
            return "Tritone Editorial"
        case .metallicChrome:
            return "Metallic Chrome"
        case .liquidMetalFlow:
            return "Liquid Metal Flow"
        case .hologram:
            return "Hologram"
        case .prismDispersion:
            return "Prism Dispersion"
        case .softBloomGlow:
            return "Soft Bloom Glow"
        case .neonGlow:
            return "Neon Glow"
        case .glassFrostedBlur:
            return "Glass / Frosted Blur"
        case .lightSweep:
            return "Light Sweep"
        case .filmGrainCinematic:
            return "Film Grain (Cinematic)"
        case .vintageFilmFade:
            return "Vintage Film Fade"
        case .vhs90sTape:
            return "VHS / 90s Tape"
        case .crtScanline:
            return "CRT Scanline"
        case .halftonePrint:
            return "Halftone Print"
        case .posterizeQuantize:
            return "Posterize / Color Quantize"
        case .glitchClean:
            return "Glitch (Clean Variant)"
        case .chromaticAberration:
            return "Chromatic Aberration"
        case .thermalHeatmap:
            return "Thermal / Heatmap"
        case .pixelSortDataMelt:
            return "Pixel Sort / Data Melt"
        }
    }

    var swatchGradient: LinearGradient {
        switch self {
        case .original:
            return LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .duotoneGradient:
            return LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.20), Color(red: 0.94, green: 0.79, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .tritoneEditorial:
            return LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.58, green: 0.48, blue: 0.36), Color(red: 0.94, green: 0.90, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .metallicChrome:
            return LinearGradient(colors: [Color(red: 0.18, green: 0.20, blue: 0.24), Color(red: 0.76, green: 0.78, blue: 0.82), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .liquidMetalFlow:
            return LinearGradient(colors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.86, green: 0.88, blue: 0.92), Color(red: 0.40, green: 0.58, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .hologram:
            return LinearGradient(colors: [Color(red: 0.26, green: 0.95, blue: 0.98), Color(red: 0.88, green: 0.44, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .prismDispersion:
            return LinearGradient(colors: [Color(red: 0.37, green: 0.71, blue: 1.0), Color(red: 0.88, green: 0.42, blue: 1.0), Color(red: 0.98, green: 0.84, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .softBloomGlow:
            return LinearGradient(colors: [Color.white, Color(red: 0.98, green: 0.76, blue: 0.56)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .neonGlow:
            return LinearGradient(colors: [Color(red: 0.12, green: 0.98, blue: 1.0), Color(red: 1.0, green: 0.28, blue: 0.80)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .glassFrostedBlur:
            return LinearGradient(colors: [Color.white.opacity(0.95), Color(red: 0.70, green: 0.90, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lightSweep:
            return LinearGradient(colors: [Color(red: 0.95, green: 0.84, blue: 0.48), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .filmGrainCinematic:
            return LinearGradient(colors: [Color(red: 0.14, green: 0.14, blue: 0.17), Color(red: 0.52, green: 0.48, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .vintageFilmFade:
            return LinearGradient(colors: [Color(red: 0.50, green: 0.36, blue: 0.24), Color(red: 0.92, green: 0.86, blue: 0.74)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .vhs90sTape:
            return LinearGradient(colors: [Color(red: 0.88, green: 0.21, blue: 0.29), Color(red: 0.21, green: 0.57, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .crtScanline:
            return LinearGradient(colors: [Color(red: 0.06, green: 0.16, blue: 0.12), Color(red: 0.34, green: 0.98, blue: 0.58)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .halftonePrint:
            return LinearGradient(colors: [Color(red: 0.27, green: 0.75, blue: 0.93), Color(red: 0.99, green: 0.54, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .posterizeQuantize:
            return LinearGradient(colors: [Color(red: 0.28, green: 0.34, blue: 0.98), Color(red: 0.98, green: 0.32, blue: 0.40), Color(red: 1.0, green: 0.82, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .glitchClean:
            return LinearGradient(colors: [.cyan, .pink, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .chromaticAberration:
            return LinearGradient(colors: [Color.red, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .thermalHeatmap:
            return LinearGradient(colors: [Color(red: 0.10, green: 0.22, blue: 1.0), Color(red: 0.18, green: 0.98, blue: 0.92), Color(red: 1.0, green: 0.82, blue: 0.12), Color(red: 1.0, green: 0.24, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .pixelSortDataMelt:
            return LinearGradient(colors: [Color(red: 0.24, green: 0.22, blue: 0.96), Color(red: 0.96, green: 0.26, blue: 0.62), Color(red: 1.0, green: 0.64, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private enum ImageRemixPalette: String, CaseIterable, Identifiable {
    case polar
    case sunlight
    case coral
    case mint
    case sky
    case lavender
    case ember
    case ink

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .polar:
            return .white
        case .sunlight:
            return Color(red: 0.98, green: 0.86, blue: 0.34)
        case .coral:
            return Color(red: 0.99, green: 0.46, blue: 0.46)
        case .mint:
            return Color(red: 0.54, green: 1.0, blue: 0.79)
        case .sky:
            return Color(red: 0.37, green: 0.87, blue: 1.0)
        case .lavender:
            return Color(red: 0.86, green: 0.68, blue: 1.0)
        case .ember:
            return Color(red: 1.0, green: 0.62, blue: 0.23)
        case .ink:
            return Color(red: 0.07, green: 0.08, blue: 0.11)
        }
    }

    var uiColor: UIColor {
        UIColor(swiftUIColor)
    }
}

private enum ImageRemixTextPlacement: String, CaseIterable, Identifiable {
    case center
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center:
            return "Center"
        case .topLeft:
            return "Top Left"
        case .topRight:
            return "Top Right"
        case .bottomLeft:
            return "Bottom Left"
        case .bottomRight:
            return "Bottom Right"
        }
    }

    var normalizedAnchorPoint: CGPoint {
        switch self {
        case .center:
            return CGPoint(x: 0.5, y: 0.5)
        case .topLeft:
            return CGPoint(x: 0.28, y: 0.18)
        case .topRight:
            return CGPoint(x: 0.72, y: 0.18)
        case .bottomLeft:
            return CGPoint(x: 0.28, y: 0.82)
        case .bottomRight:
            return CGPoint(x: 0.72, y: 0.82)
        }
    }

    var previewPoint: CGPoint {
        switch self {
        case .center:
            return CGPoint(x: 0.5, y: 0.5)
        case .topLeft:
            return CGPoint(x: 0.24, y: 0.24)
        case .topRight:
            return CGPoint(x: 0.76, y: 0.24)
        case .bottomLeft:
            return CGPoint(x: 0.24, y: 0.76)
        case .bottomRight:
            return CGPoint(x: 0.76, y: 0.76)
        }
    }

    var containerAlignment: Alignment {
        switch self {
        case .center:
            return .center
        case .topLeft:
            return .topLeading
        case .topRight:
            return .topTrailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        }
    }

    var textFrameAlignment: Alignment {
        switch self {
        case .center:
            return .center
        case .topLeft, .bottomLeft:
            return .leading
        case .topRight, .bottomRight:
            return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .center:
            return .center
        case .topLeft, .bottomLeft:
            return .leading
        case .topRight, .bottomRight:
            return .trailing
        }
    }

    func canvasInsets(for canvasSize: CGSize) -> EdgeInsets {
        let horizontal = max(canvasSize.width * 0.06, 22)
        let vertical = max(canvasSize.height * 0.05, 20)
        return EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}

private struct ImageRemixStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var palette: ImageRemixPalette
    var lineWidth: CGFloat
}

private struct ImageRemixTextOverlay: Identifiable {
    let id = UUID()
    var text: String
    var palette: ImageRemixPalette
    var scale: CGFloat
    var position: CGPoint
    var placement: ImageRemixTextPlacement?
}

private struct ImageRemixStickerOverlay: Identifiable {
    let id = UUID()
    var emoji: String
    var scale: CGFloat
    var position: CGPoint
}

private struct ImageRemixEmojiEntry: Identifiable, Hashable {
    let emoji: String
    let keywords: String

    var id: String { emoji }

    func matches(searchTerm: String) -> Bool {
        let normalized = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return emoji.contains(normalized) || keywords.contains(normalized)
    }

    static let featured: [ImageRemixEmojiEntry] = [
        entry("🔥", "fire hot flame lit"),
        entry("✨", "sparkles magic shine shimmer"),
        entry("👀", "eyes look watch"),
        entry("💥", "boom blast impact"),
        entry("😭", "cry sob tears"),
        entry("😎", "cool sunglasses vibe"),
        entry("🫧", "bubbles dreamy"),
        entry("🪩", "disco party sparkle"),
        entry("🌈", "rainbow colorful pride"),
        entry("⚡️", "lightning electric energy"),
        entry("🎉", "celebration confetti party"),
        entry("🛸", "ufo alien space")
    ]

    static let catalog: [ImageRemixEmojiEntry] = [
        entry("🔥", "fire hot flame lit energy"),
        entry("✨", "sparkles magic shimmer shine"),
        entry("💥", "boom blast impact explode"),
        entry("💫", "dizzy stars magic swirl"),
        entry("⭐️", "star favorite shine"),
        entry("🌟", "glowing star shine bright"),
        entry("⚡️", "lightning electric charge power"),
        entry("☄️", "comet meteor space"),
        entry("🌈", "rainbow colorful pride sky"),
        entry("🫧", "bubbles dreamy underwater foam"),
        entry("☀️", "sun sunshine warm bright"),
        entry("🌙", "moon night crescent"),
        entry("❄️", "snow cold winter flake"),
        entry("🌊", "wave ocean water beach"),
        entry("🌸", "blossom flower pink spring"),
        entry("🌹", "rose flower romance"),
        entry("🌼", "daisy flower bloom"),
        entry("🌻", "sunflower flower summer"),
        entry("🍀", "clover luck green"),
        entry("🌵", "cactus desert"),
        entry("🪴", "plant leaves home"),
        entry("🦋", "butterfly flutter"),
        entry("🐝", "bee honey buzz"),
        entry("🐸", "frog silly green"),
        entry("🦄", "unicorn magical fantasy"),
        entry("🐶", "dog puppy pet"),
        entry("🐱", "cat kitty pet"),
        entry("👀", "eyes look watch stare"),
        entry("🧠", "brain smart idea thinking"),
        entry("💎", "diamond gem luxury"),
        entry("👑", "crown king queen royalty"),
        entry("🕶️", "sunglasses cool shades"),
        entry("📼", "vhs tape retro nineties"),
        entry("📸", "camera photo picture"),
        entry("🎬", "clapper film movie cinema"),
        entry("🎞️", "film strip movie reel"),
        entry("🎧", "headphones music audio"),
        entry("🎤", "microphone sing karaoke"),
        entry("🎹", "piano keys music"),
        entry("🎸", "guitar rock music"),
        entry("🥁", "drum beat music"),
        entry("💿", "disc cd music retro"),
        entry("🪩", "disco ball dance party"),
        entry("🪄", "magic wand spell"),
        entry("🛸", "ufo alien spaceship"),
        entry("🚀", "rocket launch space"),
        entry("🪐", "planet saturn space"),
        entry("🌍", "earth globe world"),
        entry("🎉", "party celebration confetti"),
        entry("🎊", "confetti celebration party"),
        entry("🎈", "balloon party float"),
        entry("🎁", "gift present box"),
        entry("🎀", "bow ribbon cute"),
        entry("🥳", "party face celebrate"),
        entry("😎", "cool sunglasses chill"),
        entry("😄", "smile happy grin"),
        entry("😁", "grin smile happy"),
        entry("😂", "laugh tears funny"),
        entry("🤣", "rolling laugh hilarious"),
        entry("😊", "blush smile sweet"),
        entry("😍", "heart eyes love"),
        entry("😘", "kiss love hearts"),
        entry("🥹", "teary grateful soft"),
        entry("😭", "cry sob tears sad"),
        entry("🥲", "smile cry bittersweet"),
        entry("😅", "sweat smile relief"),
        entry("😮‍💨", "exhale sigh relief"),
        entry("😴", "sleep tired snooze"),
        entry("🫠", "melting awkward oops"),
        entry("🤯", "mind blown shocked"),
        entry("😵‍💫", "dizzy spiral overwhelmed"),
        entry("😡", "angry mad rage"),
        entry("😤", "huff annoyed frustrated"),
        entry("🥶", "freezing cold icy"),
        entry("🥵", "hot sweating"),
        entry("🤠", "cowboy yeehaw western"),
        entry("🤡", "clown chaos silly"),
        entry("👻", "ghost spooky"),
        entry("💀", "skull dead funny"),
        entry("☠️", "skull crossbones danger"),
        entry("👽", "alien outer space"),
        entry("🤖", "robot tech future"),
        entry("❤️", "heart love red"),
        entry("🩷", "pink heart love"),
        entry("🧡", "orange heart love"),
        entry("💛", "yellow heart love"),
        entry("💚", "green heart love"),
        entry("🩵", "light blue heart love"),
        entry("💙", "blue heart love"),
        entry("💜", "purple heart love"),
        entry("🖤", "black heart love"),
        entry("🤍", "white heart love"),
        entry("🤎", "brown heart love"),
        entry("💔", "broken heart heartbreak"),
        entry("❤️‍🔥", "heart on fire passion"),
        entry("💕", "two hearts love"),
        entry("💖", "sparkle heart love"),
        entry("💘", "heart arrow crush"),
        entry("🫶", "heart hands love"),
        entry("👏", "clap applause"),
        entry("🙌", "raise hands celebrate"),
        entry("🙏", "pray thanks hope"),
        entry("👍", "thumbs up yes like"),
        entry("👎", "thumbs down no dislike"),
        entry("✌️", "peace victory two"),
        entry("🤞", "cross fingers luck"),
        entry("👌", "ok hand perfect"),
        entry("💅", "nails sass glam"),
        entry("☕️", "coffee espresso drink"),
        entry("🍕", "pizza slice food"),
        entry("🍔", "burger food"),
        entry("🍟", "fries snack food"),
        entry("🍓", "strawberry fruit sweet"),
        entry("🍒", "cherries fruit sweet"),
        entry("🍑", "peach fruit"),
        entry("🍸", "cocktail martini drink"),
        entry("🍷", "wine drink"),
        entry("🥂", "cheers toast glasses"),
        entry("🏁", "finish racing flag"),
        entry("🏆", "trophy winner victory"),
        entry("⚽️", "soccer football ball"),
        entry("🏀", "basketball sports"),
        entry("💯", "hundred score hype"),
        entry("✅", "check yes done"),
        entry("❌", "x no wrong"),
        entry("⚠️", "warning caution alert"),
        entry("🚨", "alarm siren alert"),
        entry("🔮", "crystal ball future"),
        entry("🪞", "mirror reflection"),
        entry("🧸", "teddy cute toy"),
        entry("🛼", "roller skate retro"),
        entry("🌐", "internet web globe")
    ]

    private static func entry(_ emoji: String, _ keywords: String) -> ImageRemixEmojiEntry {
        ImageRemixEmojiEntry(emoji: emoji, keywords: keywords.lowercased())
    }
}

private struct ImageRemixStaticCompositionView: View {
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

private struct ImageRemixToolButtonLabel: View {
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

private struct ImageRemixFilterPresetChip: View {
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

private struct ImageRemixStickerLibraryBadge: View {
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

private struct ImageRemixDrawingLayer: View {
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

private struct ImageRemixDraggableTextOverlayView: View {
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

private struct ImageRemixDraggableStickerOverlayView: View {
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

private struct ImageRemixTextOverlayLabel: View {
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

private struct ImageRemixStickerOverlayLabel: View {
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

private struct ImageRemixPaletteStrip: View {
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

private struct ImageRemixTextPlacementPicker: View {
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

private struct ImageRemixAccentButtonStyle: ButtonStyle {
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

private struct ImageRemixSecondaryButtonStyle: ButtonStyle {
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

private enum ImageRemixFilterProcessor {
    private static let context = CIContext(options: nil)

    static func renderedImage(for preset: ImageRemixFilterPreset, from image: UIImage) -> UIImage {
        let baseImage = image.flowNormalizedUp()
        guard let ciImage = CIImage(image: baseImage) else {
            return baseImage
        }

        switch preset {
        case .original:
            return baseImage

        case .duotoneGradient:
            return duotoneGradientImage(from: ciImage, baseImage: baseImage)
        case .tritoneEditorial:
            return tritoneEditorialImage(from: ciImage, baseImage: baseImage)
        case .metallicChrome:
            return metallicChromeImage(from: ciImage, baseImage: baseImage)
        case .liquidMetalFlow:
            return liquidMetalFlowImage(from: ciImage, baseImage: baseImage)
        case .hologram:
            return hologramImage(from: ciImage, baseImage: baseImage)
        case .prismDispersion:
            return prismDispersionImage(from: ciImage, baseImage: baseImage)
        case .softBloomGlow:
            return softBloomGlowImage(from: ciImage, baseImage: baseImage)
        case .neonGlow:
            return neonGlowImage(from: ciImage, baseImage: baseImage)
        case .glassFrostedBlur:
            return glassFrostedBlurImage(from: ciImage, baseImage: baseImage)
        case .lightSweep:
            return lightSweepImage(from: ciImage, baseImage: baseImage)
        case .filmGrainCinematic:
            return filmGrainCinematicImage(from: ciImage, baseImage: baseImage)
        case .vintageFilmFade:
            return vintageFilmFadeImage(from: ciImage, baseImage: baseImage)
        case .vhs90sTape:
            return vhs90sTapeImage(from: ciImage, baseImage: baseImage)
        case .crtScanline:
            return crtScanlineImage(from: ciImage, baseImage: baseImage)
        case .halftonePrint:
            return halftonePrintImage(from: ciImage, baseImage: baseImage)
        case .posterizeQuantize:
            return posterizeQuantizeImage(from: ciImage, baseImage: baseImage)
        case .glitchClean:
            return glitchCleanImage(from: ciImage, baseImage: baseImage)
        case .chromaticAberration:
            return chromaticAberrationImage(from: ciImage, baseImage: baseImage)
        case .thermalHeatmap:
            return thermalHeatmapImage(from: ciImage, baseImage: baseImage)
        case .pixelSortDataMelt:
            return pixelSortDataMeltImage(from: ciImage, baseImage: baseImage)
        }
    }

    private static func duotoneGradientImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let toned = ciImage
            .applyingPhotoEffect(.mono)
            .applyingColorControls(saturation: 0, brightness: 0.03, contrast: 1.18)
        let mapped = colorMapped(toned, colors: [
            UIColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1),
            UIColor(red: 0.98, green: 0.76, blue: 0.32, alpha: 1)
        ]) ?? toned
        let duotoneBase = renderedUIImage(from: mapped) ?? baseImage
        return overlay(on: duotoneBase) { context, size in
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor.clear,
                    UIColor(red: 0.18, green: 0.70, blue: 1.0, alpha: 0.12),
                    UIColor(red: 1.0, green: 0.60, blue: 0.24, alpha: 0.18),
                    UIColor.clear
                ],
                locations: [0, 0.26, 0.74, 1],
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                blendMode: .softLight
            )
        }
    }

    private static func tritoneEditorialImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let toned = ciImage
            .applyingPhotoEffect(.tonal)
            .applyingColorControls(saturation: 0.18, brightness: 0.02, contrast: 1.22)
        let mapped = colorMapped(toned, colors: [
            UIColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1),
            UIColor(red: 0.56, green: 0.48, blue: 0.38, alpha: 1),
            UIColor(red: 0.95, green: 0.91, blue: 0.84, alpha: 1)
        ]) ?? toned
        let editorialBase = renderedUIImage(from: mapped) ?? baseImage
        return overlay(on: editorialBase) { context, size in
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor(red: 0.98, green: 0.82, blue: 0.64, alpha: 0.10),
                    UIColor.clear
                ],
                locations: [0, 1],
                start: CGPoint(x: size.width * 0.1, y: 0),
                end: CGPoint(x: size.width * 0.85, y: size.height),
                blendMode: .screen
            )
            drawFilmGrain(in: context, size: size, alpha: 0.025, spacing: 4.8)
        }
    }

    private static func metallicChromeImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let monochrome = ciImage
            .applyingPhotoEffect(.mono)
            .applyingGammaAdjust(power: 0.78)
            .applyingColorControls(saturation: 0, brightness: 0.05, contrast: 1.42)
        let mapped = colorMapped(monochrome, colors: [
            UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1),
            UIColor(red: 0.32, green: 0.35, blue: 0.40, alpha: 1),
            UIColor(red: 0.76, green: 0.79, blue: 0.83, alpha: 1),
            UIColor.white
        ]) ?? monochrome
        let chromeBase = renderedUIImage(from: mapped) ?? baseImage
        return overlay(on: chromeBase) { context, size in
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor.clear,
                    UIColor.white.withAlphaComponent(0.42),
                    UIColor.clear
                ],
                locations: [0.18, 0.52, 0.86],
                start: CGPoint(x: size.width * 0.08, y: size.height),
                end: CGPoint(x: size.width * 0.78, y: 0),
                blendMode: .screen
            )
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor(red: 0.36, green: 0.46, blue: 0.62, alpha: 0.18),
                    UIColor.clear
                ],
                locations: [0, 1],
                start: CGPoint(x: 0, y: size.height * 0.9),
                end: CGPoint(x: size.width, y: size.height * 0.15),
                blendMode: .softLight
            )
        }
    }

    private static func liquidMetalFlowImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let chromeBase = metallicChromeImage(from: ciImage, baseImage: baseImage)
        return overlay(on: chromeBase) { context, size in
            drawHorizontalDisplacement(
                from: chromeBase,
                in: context,
                size: size,
                stripHeight: max(size.height / 54, 10),
                maxShift: max(size.width * 0.014, 4.5),
                alpha: 0.95,
                blendMode: .normal,
                phase: 0.8,
                frequency: 0.58,
                yRange: 0.0...1.0
            )
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor.clear,
                    UIColor.white.withAlphaComponent(0.22),
                    UIColor.clear
                ],
                locations: [0.08, 0.42, 0.82],
                start: CGPoint(x: size.width * 0.2, y: size.height),
                end: CGPoint(x: size.width * 0.95, y: 0),
                blendMode: .screen
            )
        }
    }

    private static func hologramImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let vivid = ciImage
            .applyingColorControls(saturation: 1.28, brightness: 0.03, contrast: 1.16)
            .applyingHueAdjust(angle: 0.32)
        let hologramBase = renderedUIImage(from: vivid) ?? baseImage
        return overlay(on: hologramBase) { context, size in
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor(red: 0.18, green: 0.96, blue: 1.0, alpha: 0.52),
                    UIColor(red: 0.86, green: 0.48, blue: 1.0, alpha: 0.38),
                    UIColor.white.withAlphaComponent(0.14)
                ],
                locations: [0, 0.55, 1],
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                blendMode: .screen
            )
            drawScanlines(in: context, size: size, alpha: 0.09, spacing: 6)
        }
    }

    private static func prismDispersionImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let crisp = ciImage
            .applyingColorControls(saturation: 1.06, brightness: 0.02, contrast: 1.18)
            .applyingBloom(radius: 5.5, intensity: 0.12)
        let prismBase = renderedUIImage(from: crisp) ?? baseImage
        return overlay(on: prismBase) { context, size in
            tinted(prismBase, color: UIColor(red: 1.0, green: 0.24, blue: 0.20, alpha: 0.18))
                .draw(at: CGPoint(x: -5, y: 0), blendMode: .screen, alpha: 1)
            tinted(prismBase, color: UIColor(red: 0.18, green: 0.84, blue: 1.0, alpha: 0.18))
                .draw(at: CGPoint(x: 5, y: 0), blendMode: .screen, alpha: 1)
            tinted(prismBase, color: UIColor(red: 1.0, green: 0.92, blue: 0.25, alpha: 0.12))
                .draw(at: CGPoint(x: 0, y: -2), blendMode: .screen, alpha: 1)
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor.clear,
                    UIColor.white.withAlphaComponent(0.12),
                    UIColor.clear
                ],
                locations: [0.12, 0.54, 0.9],
                start: CGPoint(x: size.width * 0.05, y: size.height),
                end: CGPoint(x: size.width * 0.88, y: 0),
                blendMode: .screen
            )
        }
    }

    private static func softBloomGlowImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let glow = ciImage
            .applyingColorControls(saturation: 1.02, brightness: 0.03, contrast: 1.08)
            .applyingBloom(radius: 20, intensity: 0.72)
        let bloomedBase = renderedUIImage(from: glow) ?? baseImage
        return overlay(on: bloomedBase) { context, size in
            drawRadialGlow(
                in: context,
                size: size,
                center: CGPoint(x: size.width * 0.52, y: size.height * 0.44),
                colors: [
                    UIColor.white.withAlphaComponent(0.12),
                    UIColor(red: 1.0, green: 0.82, blue: 0.70, alpha: 0.08),
                    UIColor.clear
                ],
                radius: max(size.width, size.height) * 0.72,
                blendMode: .screen
            )
        }
    }

    private static func neonGlowImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let punchy = ciImage
            .applyingColorControls(saturation: 1.34, brightness: 0.03, contrast: 1.2)
            .applyingBloom(radius: 18, intensity: 0.86)
        let neonBase = renderedUIImage(from: punchy) ?? baseImage
        return overlay(on: neonBase) { context, size in
            tinted(neonBase, color: UIColor(red: 0.12, green: 0.98, blue: 1.0, alpha: 0.16))
                .draw(at: CGPoint(x: -4, y: 0), blendMode: .screen, alpha: 1)
            tinted(neonBase, color: UIColor(red: 1.0, green: 0.24, blue: 0.74, alpha: 0.16))
                .draw(at: CGPoint(x: 4, y: 0), blendMode: .screen, alpha: 1)
            drawRadialGlow(
                in: context,
                size: size,
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                colors: [
                    UIColor(red: 0.14, green: 0.92, blue: 1.0, alpha: 0.08),
                    UIColor.clear
                ],
                radius: max(size.width, size.height) * 0.85,
                blendMode: .screen
            )
        }
    }

    private static func glassFrostedBlurImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let frosted = ciImage
            .applyingGaussianBlur(radius: 10)
            .applyingColorControls(saturation: 0.88, brightness: 0.06, contrast: 0.94)
        let glassBase = renderedUIImage(from: frosted) ?? baseImage
        return overlay(on: glassBase) { context, size in
            baseImage.draw(in: CGRect(origin: .zero, size: size), blendMode: .softLight, alpha: 0.16)
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor.white.withAlphaComponent(0.18),
                    UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 0.08),
                    UIColor.clear
                ],
                locations: [0, 0.38, 1],
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                blendMode: .screen
            )
        }
    }

    private static func lightSweepImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let polished = ciImage
            .applyingColorControls(saturation: 1.02, brightness: 0.01, contrast: 1.12)
        let sweepBase = renderedUIImage(from: polished) ?? baseImage
        return overlay(on: sweepBase) { context, size in
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor.clear,
                    UIColor.white.withAlphaComponent(0.46),
                    UIColor.clear
                ],
                locations: [0.18, 0.48, 0.78],
                start: CGPoint(x: size.width * 0.15, y: size.height),
                end: CGPoint(x: size.width * 0.82, y: 0),
                blendMode: .screen
            )
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor.clear,
                    UIColor(red: 1.0, green: 0.84, blue: 0.44, alpha: 0.14),
                    UIColor.clear
                ],
                locations: [0.1, 0.46, 0.84],
                start: CGPoint(x: size.width * 0.2, y: size.height),
                end: CGPoint(x: size.width * 0.88, y: 0),
                blendMode: .softLight
            )
        }
    }

    private static func filmGrainCinematicImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let graded = ciImage
            .applyingColorControls(saturation: 0.94, brightness: -0.01, contrast: 1.14)
            .applyingExposureAdjust(ev: -0.02)
        let grainBase = renderedUIImage(from: graded) ?? baseImage
        return overlay(on: grainBase) { context, size in
            drawFilmGrain(in: context, size: size, alpha: 0.06, spacing: 4.2)
            drawRadialGlow(
                in: context,
                size: size,
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                colors: [
                    UIColor.clear,
                    UIColor.clear,
                    UIColor.black.withAlphaComponent(0.22)
                ],
                radius: max(size.width, size.height) * 0.82,
                blendMode: .multiply
            )
        }
    }

    private static func vintageFilmFadeImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let faded = ciImage
            .applyingColorControls(saturation: 0.72, brightness: 0.06, contrast: 0.88)
            .applyingSepia(intensity: 0.14)
        let vintageBase = renderedUIImage(from: faded) ?? baseImage
        return overlay(on: vintageBase) { context, size in
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor(red: 1.0, green: 0.92, blue: 0.78, alpha: 0.16),
                    UIColor.clear
                ],
                locations: [0, 1],
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                blendMode: .screen
            )
            drawFilmGrain(in: context, size: size, alpha: 0.035, spacing: 5.2)
        }
    }

    private static func vhs90sTapeImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let adjusted = ciImage
            .applyingColorControls(saturation: 1.12, brightness: -0.01, contrast: 1.08)
            .applyingExposureAdjust(ev: 0.05)
        let vhsBase = renderedUIImage(from: adjusted) ?? baseImage
        return overlay(on: vhsBase) { context, size in
            let redGhost = tinted(vhsBase, color: UIColor(red: 1.0, green: 0.2, blue: 0.26, alpha: 0.24))
            let blueGhost = tinted(vhsBase, color: UIColor(red: 0.20, green: 0.54, blue: 1.0, alpha: 0.22))
            redGhost.draw(at: CGPoint(x: -6, y: 0), blendMode: .screen, alpha: 1)
            blueGhost.draw(at: CGPoint(x: 6, y: 0), blendMode: .screen, alpha: 1)
            drawScanlines(in: context, size: size, alpha: 0.12, spacing: 4.5)
            context.setBlendMode(.plusLighter)
            UIColor.white.withAlphaComponent(0.08).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.78, width: size.width, height: 2))
        }
    }

    private static func crtScanlineImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let crt = ciImage
            .applyingColorControls(saturation: 0.98, brightness: 0.01, contrast: 1.08)
        let crtBase = renderedUIImage(from: crt) ?? baseImage
        return overlay(on: crtBase) { context, size in
            drawScanlines(in: context, size: size, alpha: 0.1, spacing: 3.3)
            context.saveGState()
            context.setBlendMode(.screen)
            stride(from: 0.0, through: size.width, by: 3).forEach { x in
                let tint = x.truncatingRemainder(dividingBy: 9)
                let color: UIColor
                switch tint {
                case 0..<3:
                    color = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.018)
                case 3..<6:
                    color = UIColor(red: 0.18, green: 1.0, blue: 0.4, alpha: 0.018)
                default:
                    color = UIColor(red: 0.18, green: 0.64, blue: 1.0, alpha: 0.018)
                }
                color.setFill()
                context.fill(CGRect(x: x, y: 0, width: 1, height: size.height))
            }
            context.restoreGState()
        }
    }

    private static func halftonePrintImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let halftone = CIFilter.cmykHalftone()
        halftone.inputImage = ciImage
        halftone.width = 7
        halftone.sharpness = 0.92
        halftone.center = CGPoint(x: ciImage.extent.midX, y: ciImage.extent.midY)
        let colorized = (halftone.outputImage ?? ciImage)
            .applyingColorControls(saturation: 1.1, brightness: 0.02, contrast: 1.08)
        return renderedUIImage(from: colorized) ?? baseImage
    }

    private static func posterizeQuantizeImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let posterized = ciImage
            .applyingColorPosterize(levels: 6)
            .applyingColorControls(saturation: 1.08, brightness: 0.01, contrast: 1.16)
        return renderedUIImage(from: posterized) ?? baseImage
    }

    private static func glitchCleanImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let punchy = ciImage
            .applyingColorControls(saturation: 1.16, brightness: 0.01, contrast: 1.18)
        let glitchBase = renderedUIImage(from: punchy) ?? baseImage
        return overlay(on: glitchBase) { context, size in
            let sliceHeight = max(size.height / 18, 14)
            for index in 0..<5 {
                let y = CGFloat(index) * sliceHeight * 1.8 + size.height * 0.08
                let height = max(sliceHeight * 0.68, 10)
                let shift = CGFloat((index % 3) - 1) * 8
                glitchBase.draw(
                    in: CGRect(x: shift, y: y, width: size.width, height: height),
                    blendMode: .screen,
                    alpha: 0.14
                )
                let tint = index.isMultiple(of: 2)
                    ? UIColor.systemCyan.withAlphaComponent(0.06)
                    : UIColor.systemPink.withAlphaComponent(0.06)
                tint.setFill()
                context.fill(CGRect(x: 0, y: y, width: size.width, height: height))
            }
        }
    }

    private static func chromaticAberrationImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let sharpened = ciImage
            .applyingColorControls(saturation: 1.08, brightness: 0, contrast: 1.14)
        let chromaBase = renderedUIImage(from: sharpened) ?? baseImage
        return overlay(on: chromaBase) { _, _ in
            tinted(chromaBase, color: UIColor(red: 1.0, green: 0.16, blue: 0.18, alpha: 0.24))
                .draw(at: CGPoint(x: -7, y: 0), blendMode: .screen, alpha: 1)
            tinted(chromaBase, color: UIColor(red: 0.18, green: 0.4, blue: 1.0, alpha: 0.24))
                .draw(at: CGPoint(x: 7, y: 0), blendMode: .screen, alpha: 1)
        }
    }

    private static func thermalHeatmapImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let mono = ciImage
            .applyingPhotoEffect(.mono)
            .applyingColorControls(saturation: 0, brightness: 0.04, contrast: 1.24)
        let mapped = colorMapped(mono, colors: [
            UIColor(red: 0.04, green: 0.12, blue: 0.86, alpha: 1),
            UIColor(red: 0.10, green: 0.52, blue: 1.0, alpha: 1),
            UIColor(red: 0.12, green: 0.96, blue: 0.88, alpha: 1),
            UIColor(red: 0.28, green: 1.0, blue: 0.44, alpha: 1),
            UIColor(red: 1.0, green: 0.88, blue: 0.16, alpha: 1),
            UIColor(red: 1.0, green: 0.46, blue: 0.14, alpha: 1),
            UIColor(red: 1.0, green: 0.14, blue: 0.12, alpha: 1)
        ])?.applyingColorControls(saturation: 1.12, brightness: 0.02, contrast: 1.08) ?? mono
        return renderedUIImage(from: mapped) ?? baseImage
    }

    private static func pixelSortDataMeltImage(from ciImage: CIImage, baseImage: UIImage) -> UIImage {
        let base = renderedUIImage(from: ciImage.applyingColorControls(saturation: 1.1, brightness: 0.01, contrast: 1.08)) ?? baseImage
        return overlay(on: base) { context, size in
            drawHorizontalDisplacement(
                from: base,
                in: context,
                size: size,
                stripHeight: max(size.height / 42, 12),
                maxShift: max(size.width * 0.045, 14),
                alpha: 1,
                blendMode: .normal,
                phase: 1.2,
                frequency: 0.34,
                yRange: 0.18...1.0
            )
            drawLinearGradient(
                in: context,
                colors: [
                    UIColor(red: 1.0, green: 0.56, blue: 0.22, alpha: 0.08),
                    UIColor(red: 0.98, green: 0.18, blue: 0.64, alpha: 0.08),
                    UIColor.clear
                ],
                locations: [0, 0.42, 1],
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: size.width, y: 0),
                blendMode: .softLight
            )
        }
    }

    private static func renderedUIImage(from ciImage: CIImage?) -> UIImage? {
        guard let ciImage else { return nil }
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func overlay(on image: UIImage, draw: (CGContext, CGSize) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { rendererContext in
            let rect = CGRect(origin: .zero, size: image.size)
            image.draw(in: rect)
            draw(rendererContext.cgContext, image.size)
        }
    }

    private static func tinted(_ image: UIImage, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: image.size)
            color.setFill()
            UIRectFill(rect)
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }

    private static func drawScanlines(in context: CGContext, size: CGSize, alpha: CGFloat, spacing: CGFloat) {
        context.saveGState()
        context.setBlendMode(.screen)
        context.setLineWidth(1)
        context.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
        stride(from: 0.0, through: size.height, by: spacing).forEach { y in
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func colorMapped(_ ciImage: CIImage, colors: [UIColor]) -> CIImage? {
        guard let gradientImage = gradientMapImage(colors: colors) else { return nil }
        guard let filter = CIFilter(name: "CIColorMap") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(gradientImage, forKey: "inputGradientImage")
        return filter.outputImage
    }

    private static func gradientMapImage(colors: [UIColor]) -> CIImage? {
        guard colors.count >= 2 else { return nil }
        let size = CGSize(width: 256, height: 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let cgColors = colors.map { $0.cgColor } as CFArray
        let locations = evenlyDistributedLocations(count: colors.count)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererContext in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: cgColors,
                locations: locations
            ) else {
                return
            }

            rendererContext.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: 0),
                options: []
            )
        }
        return CIImage(image: image)
    }

    private static func drawLinearGradient(
        in context: CGContext,
        colors: [UIColor],
        locations: [CGFloat],
        start: CGPoint,
        end: CGPoint,
        blendMode: CGBlendMode
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        ) else {
            return
        }

        context.saveGState()
        context.setBlendMode(blendMode)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }

    private static func drawRadialGlow(
        in context: CGContext,
        size: CGSize,
        center: CGPoint,
        colors: [UIColor],
        radius: CGFloat,
        blendMode: CGBlendMode
    ) {
        let locations = evenlyDistributedLocations(count: colors.count)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map { $0.cgColor } as CFArray,
            locations: locations
        ) else {
            return
        }

        context.saveGState()
        context.setBlendMode(blendMode)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
        context.restoreGState()
    }

    private static func evenlyDistributedLocations(count: Int) -> [CGFloat] {
        guard count > 1 else { return [0] }
        let lastIndex = CGFloat(count - 1)
        return (0..<count).map { CGFloat($0) / lastIndex }
    }

    private static func drawFilmGrain(in context: CGContext, size: CGSize, alpha: CGFloat, spacing: CGFloat) {
        context.saveGState()
        context.setBlendMode(.overlay)

        for y in stride(from: 0.0, to: size.height, by: spacing) {
            for x in stride(from: 0.0, to: size.width, by: spacing) {
                let noise = deterministicNoise(x: x, y: y)
                let grainAlpha = max(0, noise - 0.54) * alpha * 1.8
                guard grainAlpha > 0 else { continue }
                let whiteValue = noise > 0.78 ? 1.0 : 0.0
                UIColor(white: whiteValue, alpha: grainAlpha).setFill()
                context.fill(CGRect(x: x, y: y, width: spacing * 0.56, height: spacing * 0.56))
            }
        }

        context.restoreGState()
    }

    private static func deterministicNoise(x: CGFloat, y: CGFloat) -> CGFloat {
        let value = sin((x * 12.9898) + (y * 78.233)) * 43758.5453
        return value - floor(value)
    }

    private static func drawHorizontalDisplacement(
        from image: UIImage,
        in context: CGContext,
        size: CGSize,
        stripHeight: CGFloat,
        maxShift: CGFloat,
        alpha: CGFloat,
        blendMode: CGBlendMode,
        phase: CGFloat,
        frequency: CGFloat,
        yRange: ClosedRange<CGFloat>
    ) {
        guard let cgImage = image.cgImage else { return }

        let scale = image.scale
        let sourceBounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let minY = size.height * yRange.lowerBound
        let maxY = size.height * yRange.upperBound

        context.saveGState()
        context.setBlendMode(blendMode)
        context.setAlpha(alpha)

        for stripeIndex in 0..<Int(ceil(size.height / stripHeight)) {
            let y = CGFloat(stripeIndex) * stripHeight
            guard y >= minY, y <= maxY else { continue }

            let height = min(stripHeight, size.height - y)
            let shift = sin(CGFloat(stripeIndex) * frequency + phase) * maxShift
                + cos(CGFloat(stripeIndex) * frequency * 0.47 + phase * 0.65) * maxShift * 0.34
            guard abs(shift) > 0.8 else { continue }

            let cropRect = CGRect(
                x: 0,
                y: y * scale,
                width: sourceBounds.width,
                height: height * scale
            ).integral.intersection(sourceBounds)
            guard let strip = cgImage.cropping(to: cropRect) else { continue }

            context.draw(strip, in: CGRect(x: shift, y: y, width: size.width, height: height))
        }

        context.restoreGState()
    }
}

private enum ImageRemixPhotoLibrary {
    enum SaveError: LocalizedError {
        case failed

        var errorDescription: String? {
            "Couldn't save that image right now."
        }
    }

    static func requestWriteAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
        default:
            return current
        }
    }

    static func save(image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: SaveError.failed)
                }
            }
        }
    }
}

private extension CIImage {
    func applyingColorControls(saturation: Float, brightness: Float, contrast: Float) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = self
        filter.saturation = saturation
        filter.brightness = brightness
        filter.contrast = contrast
        return filter.outputImage ?? self
    }

    func applyingHueAdjust(angle: Float) -> CIImage {
        let filter = CIFilter.hueAdjust()
        filter.inputImage = self
        filter.angle = angle
        return filter.outputImage ?? self
    }

    func applyingExposureAdjust(ev: Float) -> CIImage {
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = self
        filter.ev = ev
        return filter.outputImage ?? self
    }

    func applyingGammaAdjust(power: Float) -> CIImage {
        let filter = CIFilter.gammaAdjust()
        filter.inputImage = self
        filter.power = power
        return filter.outputImage ?? self
    }

    func applyingBloom(radius: Float, intensity: Float) -> CIImage {
        let filter = CIFilter.bloom()
        filter.inputImage = self
        filter.radius = radius
        filter.intensity = intensity
        return filter.outputImage?.cropped(to: extent) ?? self
    }

    func applyingGaussianBlur(radius: Float) -> CIImage {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = self
        filter.radius = radius
        return filter.outputImage?.cropped(to: extent) ?? self
    }

    func applyingColorPosterize(levels: Float) -> CIImage {
        let filter = CIFilter.colorPosterize()
        filter.inputImage = self
        filter.levels = levels
        return filter.outputImage ?? self
    }

    func applyingSepia(intensity: Float) -> CIImage {
        let filter = CIFilter.sepiaTone()
        filter.inputImage = self
        filter.intensity = intensity
        return filter.outputImage ?? self
    }

    func applyingPhotoEffect(_ effect: ImageRemixPhotoEffect) -> CIImage {
        switch effect {
        case .mono:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = self
            return filter.outputImage ?? self
        case .tonal:
            let filter = CIFilter.photoEffectTonal()
            filter.inputImage = self
            return filter.outputImage ?? self
        case .process:
            let filter = CIFilter.photoEffectProcess()
            filter.inputImage = self
            return filter.outputImage ?? self
        }
    }
}

private enum ImageRemixPhotoEffect {
    case mono
    case tonal
    case process
}

private extension UIImage {
    func flowNormalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func flowPreparedForRemix(maxDimension: CGFloat) -> UIImage {
        let normalized = flowNormalizedUp()
        let longestSide = max(normalized.size.width, normalized.size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return normalized }

        let resizeScale = maxDimension / longestSide
        let targetSize = CGSize(
            width: normalized.size.width * resizeScale,
            height: normalized.size.height * resizeScale
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension String {
    var firstEmojiCluster: String? {
        for character in self {
            let cluster = String(character)
            if cluster.unicodeScalars.contains(where: { $0.properties.isEmoji || $0.properties.isEmojiPresentation }) {
                return cluster
            }
        }
        return nil
    }
}

private extension CGPoint {
    func clampedToUnitSquare() -> CGPoint {
        CGPoint(
            x: x.clamped(to: 0...1),
            y: y.clamped(to: 0...1)
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
