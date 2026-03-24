import SwiftUI

private struct ReactionFloatingHeart: Identifiable, Equatable {
    let id = UUID()
    let xDrift: CGFloat
    let yTravel: CGFloat
    let rotation: Double
    let startScale: CGFloat
    let endScale: CGFloat
    let size: CGFloat
    let duration: Double
    let opacity: Double
}

struct ReactionButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let isLiked: Bool
    let count: Int
    var activeColor: Color = .red
    var inactiveColor: Color = .secondary
    var minWidth: CGFloat = 34
    var minHeight: CGFloat = 28
    var alignment: Alignment = .leading
    var accessibilityLabel: String = "Like"
    let action: () -> Void

    @State private var heartScale: CGFloat = 1
    @State private var burstTrigger = 0
    @State private var isPressing = false
    @State private var longHoldActivated = false
    @State private var floatingHearts: [ReactionFloatingHeart] = []
    @State private var holdActivationTask: Task<Void, Never>?
    @State private var floatingHeartTask: Task<Void, Never>?

    private let longHoldDurationNanos: UInt64 = 420_000_000
    private let maxTapTranslation: CGFloat = 24

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                floatingHeartOverlay
                ReactionSparkleBurstView(trigger: burstTrigger, tint: activeColor)
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .scaleEffect(heartScale)
            }
            .frame(width: 20, height: 20)

            if count > 0 {
                Text("\(count)")
                    .font(.footnote)
            }
        }
        .frame(minWidth: minWidth, minHeight: minHeight, alignment: alignment)
        .buttonStyle(.plain)
        .foregroundStyle(isLiked ? activeColor : inactiveColor)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled else { return }
            action()
        }
        .onChange(of: isLiked) { oldValue, newValue in
            guard newValue && !oldValue else { return }
            burstTrigger += 1
            animateLikePop()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled else { return }
                    beginPressIfNeeded()
                }
                .onEnded { value in
                    guard isEnabled else {
                        resetPressState()
                        return
                    }
                    let translation = value.translation
                    let shouldTriggerTap = !longHoldActivated
                        && abs(translation.width) <= maxTapTranslation
                        && abs(translation.height) <= maxTapTranslation
                    resetPressState()
                    if shouldTriggerTap {
                        action()
                    }
                }
        )
        .onDisappear {
            resetPressState()
        }
    }

    @ViewBuilder
    private var floatingHeartOverlay: some View {
        ZStack {
            ForEach(floatingHearts) { heart in
                FloatingReactionHeartView(heart: heart, tint: activeColor)
            }
        }
        .frame(width: 78, height: 92)
        .offset(y: -12)
        .allowsHitTesting(false)
    }

    @MainActor
    private func animateLikePop() {
        Task {
            heartScale = 0.82
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                heartScale = 1.24
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                heartScale = 1
            }
        }
    }

    @MainActor
    private func beginPressIfNeeded() {
        guard !isPressing else { return }
        isPressing = true
        longHoldActivated = false
        startHoldActivationTask()
    }

    @MainActor
    private func startHoldActivationTask() {
        holdActivationTask?.cancel()
        holdActivationTask = Task {
            try? await Task.sleep(nanoseconds: longHoldDurationNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isPressing else { return }
                longHoldActivated = true
                startFloatingHeartLoop()
                if !isLiked {
                    action()
                }
            }
        }
    }

    @MainActor
    private func startFloatingHeartLoop() {
        floatingHeartTask?.cancel()
        spawnFloatingHeart()
        floatingHeartTask = Task {
            while !Task.isCancelled {
                let delay = UInt64(Double.random(in: 0.09...0.16) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard isPressing, longHoldActivated else { return }
                    spawnFloatingHeart()
                }
            }
        }
    }

    @MainActor
    private func spawnFloatingHeart() {
        guard isPressing, longHoldActivated else { return }

        let heart = ReactionFloatingHeart(
            xDrift: CGFloat.random(in: -18...18),
            yTravel: CGFloat.random(in: 26...62),
            rotation: Double.random(in: -18...18),
            startScale: CGFloat.random(in: 0.7...0.95),
            endScale: CGFloat.random(in: 1.05...1.35),
            size: CGFloat.random(in: 8...13),
            duration: Double.random(in: 0.95...1.45),
            opacity: Double.random(in: 0.55...0.92)
        )
        floatingHearts.append(heart)

        Task {
            let lifetime = UInt64((heart.duration + 0.2) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: lifetime)
            await MainActor.run {
                floatingHearts.removeAll { $0.id == heart.id }
            }
        }
    }

    @MainActor
    private func resetPressState() {
        isPressing = false
        longHoldActivated = false
        holdActivationTask?.cancel()
        holdActivationTask = nil
        floatingHeartTask?.cancel()
        floatingHeartTask = nil
        floatingHearts.removeAll()
    }
}

private struct ReactionSparkleBurstView: View {
    let trigger: Int
    let tint: Color

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            sparkle(angle: -120, distance: 16, rotation: -22, delay: 0)
            sparkle(angle: -35, distance: 18, rotation: 18, delay: 0.03)
            sparkle(angle: 36, distance: 17, rotation: -10, delay: 0.015)
            sparkle(angle: 118, distance: 15, rotation: 22, delay: 0.045)
        }
        .frame(width: 34, height: 34)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            playBurst()
        }
    }

    private func sparkle(angle: Double, distance: CGFloat, rotation: Double, delay: Double) -> some View {
        let xOffset = CGFloat(cos(angle * .pi / 180)) * distance
        let yOffset = CGFloat(sin(angle * .pi / 180)) * distance

        return Image(systemName: "sparkle")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(tint.opacity(isAnimating ? 0.95 : 0))
            .scaleEffect(isAnimating ? 1 : 0.25)
            .offset(
                x: isAnimating ? xOffset : 0,
                y: isAnimating ? yOffset : 0
            )
            .rotationEffect(.degrees(isAnimating ? rotation : 0))
            .animation(
                .spring(response: 0.24, dampingFraction: 0.68)
                    .delay(delay),
                value: isAnimating
            )
    }

    @MainActor
    private func playBurst() {
        Task {
            isAnimating = false
            await Task.yield()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                isAnimating = true
            }
            try? await Task.sleep(nanoseconds: 360_000_000)
            withAnimation(.easeOut(duration: 0.12)) {
                isAnimating = false
            }
        }
    }
}

private struct FloatingReactionHeartView: View {
    let heart: ReactionFloatingHeart
    let tint: Color

    @State private var animate = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: heart.size, weight: .semibold))
            .foregroundStyle(tint)
            .opacity(animate ? 0 : heart.opacity)
            .scaleEffect(animate ? heart.endScale : heart.startScale)
            .offset(
                x: animate ? heart.xDrift : 0,
                y: animate ? -heart.yTravel : 0
            )
            .rotationEffect(.degrees(animate ? heart.rotation : heart.rotation * 0.2))
            .blur(radius: animate ? 0.6 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: heart.duration)) {
                    animate = true
                }
            }
    }
}
