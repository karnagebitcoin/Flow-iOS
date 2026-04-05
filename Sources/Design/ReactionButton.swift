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

private struct ReactionSparkleParticle: Identifiable, Equatable {
    let id = UUID()
    let xDrift: CGFloat
    let yTravel: CGFloat
    let sway: CGFloat
    let rotation: Double
    let startScale: CGFloat
    let endScale: CGFloat
    let size: CGFloat
    let duration: Double
    let opacity: Double
    let blur: CGFloat
}

struct ReactionButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let isLiked: Bool
    var isBonusReaction: Bool = false
    let count: Int
    var activeColor: Color = .red
    var bonusActiveColor: Color? = nil
    var inactiveColor: Color = .secondary
    var minWidth: CGFloat = 34
    var minHeight: CGFloat = 28
    var alignment: Alignment = .leading
    var accessibilityLabel: String = "Like"
    let action: (_ bonusCount: Int) -> Void

    @State private var heartScale: CGFloat = 1
    @State private var burstTrigger = 0
    @State private var isPressing = false
    @State private var longHoldActivated = false
    @State private var floatingHearts: [ReactionFloatingHeart] = []
    @State private var longHoldBurstCount = 0
    @State private var displayedBurstCount: Int?
    @State private var holdActivationTask: Task<Void, Never>?
    @State private var holdChargeTask: Task<Void, Never>?
    @State private var floatingHeartTask: Task<Void, Never>?
    @State private var burstDisplayResetTask: Task<Void, Never>?

    private let longHoldDurationNanos: UInt64 = 420_000_000
    private let maxTapTranslation: CGFloat = 24
    private let longPressEffectScale: CGFloat = 2

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                floatingHeartOverlay
                ReactionSparkleBurstView(trigger: burstTrigger, tint: activeColor)
                Image(systemName: resolvedIsLiked ? "heart.fill" : "heart")
                    .scaleEffect(heartScale)
            }
            .frame(width: 20, height: 20)

            if let visibleBurstCount = displayedBurstCount, visibleBurstCount > 0 {
                Text("+\(visibleBurstCount)")
                    .font(.footnote.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(resolvedActiveColor)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if count > 0 {
                Text("\(count)")
                    .font(.footnote)
            }
        }
        .frame(minWidth: minWidth, minHeight: minHeight, alignment: alignment)
        .buttonStyle(.plain)
        .foregroundStyle(resolvedIsLiked ? resolvedActiveColor : inactiveColor)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled else { return }
            AppHaptics.reactionTap()
            action(0)
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
                    let chargedBonusCount = longHoldActivated ? max(longHoldBurstCount, 1) : nil
                    let shouldTriggerTap = !longHoldActivated
                        && abs(translation.width) <= maxTapTranslation
                        && abs(translation.height) <= maxTapTranslation
                    resetPressState()
                    if let chargedBonusCount {
                        action(chargedBonusCount)
                    } else if shouldTriggerTap {
                        AppHaptics.reactionTap()
                        action(0)
                    }
                }
        )
        .onDisappear {
            resetPressState()
            burstDisplayResetTask?.cancel()
            burstDisplayResetTask = nil
        }
    }

    @ViewBuilder
    private var floatingHeartOverlay: some View {
        ZStack {
            ForEach(floatingHearts) { heart in
                FloatingReactionHeartView(heart: heart, tint: activeColor)
            }
        }
        .frame(width: 104 * longPressEffectScale, height: 132 * longPressEffectScale)
        .offset(y: -22 * longPressEffectScale)
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
        longHoldBurstCount = 0
        displayedBurstCount = nil
        burstDisplayResetTask?.cancel()
        burstDisplayResetTask = nil
        guard !isLiked else { return }
        startHoldActivationTask()
        startHoldChargeTask()
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
                AppHaptics.reactionChargeCompleted()
                startFloatingHeartLoop()
            }
        }
    }

    @MainActor
    private func startHoldChargeTask() {
        holdChargeTask?.cancel()
        holdChargeTask = Task {
            let chargeSteps: [UInt64] = [110_000_000, 230_000_000, 340_000_000]

            for checkpoint in chargeSteps {
                try? await Task.sleep(nanoseconds: checkpoint)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard isPressing, !longHoldActivated else { return }
                    let progress = min(Double(checkpoint) / Double(longHoldDurationNanos), 1)
                    AppHaptics.reactionChargePulse(progress: progress)
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

        longHoldBurstCount += 1
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            // Keep burst count local to the button so the user sees the held stream
            // without implying extra protocol-level reactions.
            displayedBurstCount = longHoldBurstCount
        }

        let heart = ReactionFloatingHeart(
            xDrift: CGFloat.random(in: -60...60),
            yTravel: CGFloat.random(in: 84...176),
            rotation: Double.random(in: -28...28),
            startScale: CGFloat.random(in: 0.9...1.12),
            endScale: CGFloat.random(in: 1.28...1.82),
            size: CGFloat.random(in: 22...34),
            duration: Double.random(in: 1.05...1.6),
            opacity: Double.random(in: 0.58...0.95)
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
        let finalBurstCount = longHoldBurstCount

        isPressing = false
        longHoldActivated = false
        holdActivationTask?.cancel()
        holdActivationTask = nil
        holdChargeTask?.cancel()
        holdChargeTask = nil
        floatingHeartTask?.cancel()
        floatingHeartTask = nil
        longHoldBurstCount = 0

        burstDisplayResetTask?.cancel()
        if finalBurstCount > 0 {
            burstDisplayResetTask = Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !isPressing else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        displayedBurstCount = nil
                    }
                }
            }
        } else {
            displayedBurstCount = nil
            burstDisplayResetTask = nil
        }
    }

    private var resolvedIsLiked: Bool {
        isLiked || (isPressing && longHoldActivated)
    }

    private var resolvedActiveColor: Color {
        (isBonusReaction || (isPressing && longHoldActivated)) ? (bonusActiveColor ?? activeColor) : activeColor
    }
}

private struct ReactionSparkleBurstView: View {
    let trigger: Int
    let tint: Color

    @State private var particles: [ReactionSparkleParticle] = []

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                ReactionSparkleParticleView(particle: particle, tint: tint)
            }
        }
        .frame(width: 92, height: 92)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            emitBurst()
        }
    }

    @MainActor
    private func emitBurst() {
        let freshParticles = (0..<7).map { _ in
            ReactionSparkleParticle(
                xDrift: CGFloat.random(in: -34...34),
                yTravel: CGFloat.random(in: 28...64),
                sway: CGFloat.random(in: -10...10),
                rotation: Double.random(in: -30...30),
                startScale: CGFloat.random(in: 0.3...0.55),
                endScale: CGFloat.random(in: 0.95...1.35),
                size: CGFloat.random(in: 12...19),
                duration: Double.random(in: 0.55...0.9),
                opacity: Double.random(in: 0.65...0.96),
                blur: CGFloat.random(in: 0.2...1.1)
            )
        }

        particles.append(contentsOf: freshParticles)

        for particle in freshParticles {
            Task {
                let lifetime = UInt64((particle.duration + 0.2) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: lifetime)
                await MainActor.run {
                    particles.removeAll { $0.id == particle.id }
                }
            }
        }
    }
}

private struct ReactionSparkleParticleView: View {
    let particle: ReactionSparkleParticle
    let tint: Color

    @State private var animate = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: particle.size, weight: .bold))
            .foregroundStyle(tint.opacity(animate ? 0 : particle.opacity))
            .scaleEffect(animate ? particle.endScale : particle.startScale)
            .offset(
                x: animate ? particle.xDrift + particle.sway : 0,
                y: animate ? -particle.yTravel : 0
            )
            .rotationEffect(.degrees(animate ? particle.rotation : particle.rotation * 0.18))
            .blur(radius: animate ? particle.blur : 0)
            .onAppear {
                withAnimation(.easeOut(duration: particle.duration)) {
                    animate = true
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
