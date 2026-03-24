import SwiftUI

struct WelcomeOnboardingView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @State private var isShowingAuthSheet = false
    @State private var authInitialTab: AuthSheetTab = .signUp

    var body: some View {
        ZStack {
            FlowPaintMotionBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 56)

                VStack(spacing: 14) {
                    Text("Flow")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.97))
                        .kerning(-1.4)

                    Text("Build a feed that feels like yours.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        openAuth(tab: .signUp)
                    } label: {
                        Text("Create Account")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .foregroundStyle(Color(red: 0.06, green: 0.10, blue: 0.18))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.96))
                            )
                            .shadow(color: Color.black.opacity(0.14), radius: 18, y: 10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        openAuth(tab: .signIn)
                    } label: {
                        Text("I Already Have an Account")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .foregroundStyle(.white)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .padding(.bottom, 20)
            }
            .padding(.vertical, 32)
        }
        .fullScreenCover(isPresented: $isShowingAuthSheet) {
            AuthSheetView(
                initialTab: authInitialTab,
                availableTabs: [.signUp, .signIn]
            )
            .environmentObject(auth)
            .environmentObject(appSettings)
            .environmentObject(relaySettings)
        }
    }

    private func openAuth(tab: AuthSheetTab) {
        authInitialTab = tab
        isShowingAuthSheet = true
    }
}

private struct FlowPaintMotionBackground: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let swayX = CGFloat(sin(time * 0.05) + sin(time * 0.017 + 1.6)) * 20
                let swayY = CGFloat(cos(time * 0.043) + sin(time * 0.021 + 0.8)) * 16
                let sceneScale = 1.15 + CGFloat(sin(time * 0.028) + cos(time * 0.013 + 2.2)) * 0.018
                let sceneTilt = Angle.degrees(sin(time * 0.032) * 3.8 + cos(time * 0.018) * 1.4)

                ZStack {
                    FlowPaintBaseGradient()
                    FlowCurrentRibbonOverlay(time: time)
                        .blendMode(.screen)
                    FlowPaintBlobField(time: time)
                    FlowMarbleVeinOverlay(time: time)
                        .blendMode(.screen)
                    FlowPaintSpeckleOverlay(time: time)
                    FlowPaintHighlightOverlay()
                    FlowPaintShadeOverlay()
                }
                .frame(width: proxy.size.width * 1.22, height: proxy.size.height * 1.22)
                .rotationEffect(sceneTilt)
                .scaleEffect(sceneScale)
                .offset(x: swayX, y: swayY)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .drawingGroup()
            }
        }
    }
}

private struct FlowPaintBaseGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.07, blue: 0.19),
                Color(red: 0.04, green: 0.15, blue: 0.33),
                Color(red: 0.05, green: 0.24, blue: 0.45)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct FlowPaintBlobField: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            FlowPaintBlob(
                colors: [
                    Color(red: 0.03, green: 0.17, blue: 0.47),
                    Color(red: 0.08, green: 0.34, blue: 0.78),
                    Color(red: 0.33, green: 0.77, blue: 0.88)
                ],
                width: 560,
                height: 500,
                xOffset: CGFloat(sin(time * 0.12) + cos(time * 0.031 + 0.9)) * 92 - 42,
                yOffset: CGFloat(cos(time * 0.09) + sin(time * 0.022 + 0.3)) * -72 - 140,
                rotation: .degrees(10 + sin(time * 0.065) * 13 + cos(time * 0.018) * 4),
                blurRadius: 40,
                opacity: 0.95
            )

            FlowPaintBlob(
                colors: [
                    Color(red: 0.02, green: 0.10, blue: 0.38),
                    Color(red: 0.07, green: 0.28, blue: 0.71),
                    Color(red: 0.03, green: 0.44, blue: 0.52)
                ],
                width: 520,
                height: 620,
                xOffset: CGFloat(cos(time * 0.10) + sin(time * 0.024 + 1.9)) * -104 - 146,
                yOffset: CGFloat(sin(time * 0.08) + cos(time * 0.02 + 2.7)) * 78 + 214,
                rotation: .degrees(-24 + cos(time * 0.075) * 13 + sin(time * 0.017 + 1.1) * 5),
                blurRadius: 34,
                opacity: 0.86
            )

            FlowPaintBlob(
                colors: [
                    Color(red: 0.20, green: 0.70, blue: 0.67).opacity(0.88),
                    Color(red: 0.11, green: 0.54, blue: 0.74).opacity(0.84),
                    Color.white.opacity(0.26)
                ],
                width: 430,
                height: 350,
                xOffset: CGFloat(sin(time * 0.13) + cos(time * 0.027 + 0.4)) * 104 + 158,
                yOffset: CGFloat(cos(time * 0.11) + sin(time * 0.019 + 2.1)) * 62 + 18,
                rotation: .degrees(28 + sin(time * 0.054) * 16 + cos(time * 0.02 + 0.7) * 5),
                blurRadius: 28,
                opacity: 0.62
            )

            FlowPaintBlob(
                colors: [
                    Color(red: 0.05, green: 0.18, blue: 0.56),
                    Color(red: 0.11, green: 0.40, blue: 0.87),
                    Color(red: 0.70, green: 0.88, blue: 0.98).opacity(0.42)
                ],
                width: 340,
                height: 700,
                xOffset: CGFloat(cos(time * 0.082) + sin(time * 0.016 + 2.6)) * 80 + 188,
                yOffset: CGFloat(sin(time * 0.074) + cos(time * 0.019 + 1.4)) * 86 + 122,
                rotation: .degrees(-10 + cos(time * 0.068) * 8 + sin(time * 0.021 + 1.3) * 3),
                blurRadius: 32,
                opacity: 0.68
            )
        }
    }
}

private struct FlowPaintHighlightOverlay: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            )
            .blendMode(.screen)
    }
}

private struct FlowPaintShadeOverlay: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.12),
                        Color.clear,
                        Color.black.opacity(0.26)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

private struct FlowCurrentRibbonOverlay: View {
    private struct RibbonMetrics {
        let topY: CGFloat
        let ribbonDepth: CGFloat
        let amplitude: CGFloat
        let horizontalDrift: CGFloat
        let secondaryDrift: CGFloat
        let leftX: CGFloat
        let rightX: CGFloat
    }

    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 26))

                for index in 0..<5 {
                    let metrics = ribbonMetrics(for: index, size: size)
                    layer.fill(
                        ribbonPath(for: metrics, size: size),
                        with: ribbonShading(for: metrics)
                    )
                }
            }
        }
        .opacity(0.92)
    }

    private func ribbonMetrics(for index: Int, size: CGSize) -> RibbonMetrics {
        let progress = CGFloat(index) / 4
        let topY = size.height * (0.08 + progress * 0.19)
        let ribbonDepth = size.height * (0.11 + progress * 0.012)
        let amplitude = size.height * (0.06 + progress * 0.015)
        let horizontalDrift = CGFloat(
            sin(time * (0.07 + Double(index) * 0.009) + Double(index) * 1.4)
        ) * size.width * 0.1
        let secondaryDrift = CGFloat(
            cos(time * (0.03 + Double(index) * 0.006) + Double(index) * 0.8)
        ) * size.width * 0.06
        let leftX = -size.width * 0.24 + horizontalDrift
        let rightX = size.width * 1.24 + secondaryDrift

        return RibbonMetrics(
            topY: topY,
            ribbonDepth: ribbonDepth,
            amplitude: amplitude,
            horizontalDrift: horizontalDrift,
            secondaryDrift: secondaryDrift,
            leftX: leftX,
            rightX: rightX
        )
    }

    private func ribbonPath(for metrics: RibbonMetrics, size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: metrics.leftX, y: metrics.topY + metrics.amplitude * 0.18))
        path.addCurve(
            to: CGPoint(x: metrics.rightX, y: metrics.topY + metrics.amplitude * 0.32),
            control1: CGPoint(
                x: size.width * 0.22 + metrics.horizontalDrift,
                y: metrics.topY - metrics.amplitude
            ),
            control2: CGPoint(
                x: size.width * 0.68 + metrics.secondaryDrift,
                y: metrics.topY + metrics.amplitude * 1.15
            )
        )
        path.addCurve(
            to: CGPoint(x: metrics.leftX, y: metrics.topY + metrics.ribbonDepth),
            control1: CGPoint(
                x: size.width * 0.76 + metrics.secondaryDrift,
                y: metrics.topY + metrics.ribbonDepth + metrics.amplitude * 0.94
            ),
            control2: CGPoint(
                x: size.width * 0.26 + metrics.horizontalDrift,
                y: metrics.topY + metrics.ribbonDepth - metrics.amplitude * 0.72
            )
        )
        path.closeSubpath()
        return path
    }

    private func ribbonShading(for metrics: RibbonMetrics) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: [
                Color(red: 0.10, green: 0.38, blue: 0.86).opacity(0.22),
                Color(red: 0.18, green: 0.68, blue: 0.72).opacity(0.18),
                Color.white.opacity(0.08)
            ]),
            startPoint: CGPoint(x: metrics.leftX, y: metrics.topY),
            endPoint: CGPoint(x: metrics.rightX, y: metrics.topY + metrics.ribbonDepth)
        )
    }
}

private struct FlowPaintBlob: View {
    let colors: [Color]
    let width: CGFloat
    let height: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat
    let rotation: Angle
    let blurRadius: CGFloat
    let opacity: Double

    var body: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Ellipse()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.clear,
                                Color.white.opacity(0.12),
                                Color.clear
                            ],
                            center: .center
                        ),
                        lineWidth: 42
                    )
                    .blur(radius: blurRadius * 0.22)
            }
            .frame(width: width, height: height)
            .rotationEffect(rotation)
            .offset(x: xOffset, y: yOffset)
            .blur(radius: blurRadius)
            .opacity(opacity)
    }
}

private struct FlowMarbleVeinOverlay: View {
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 9))

                let width = size.width
                let height = size.height

                for index in 0..<8 {
                    let progress = CGFloat(index) / 7
                    let sway = CGFloat(sin(time * (0.09 + Double(index) * 0.012))) * 28
                    let drift = CGFloat(cos(time * (0.07 + Double(index) * 0.01))) * 22

                    var path = Path()
                    path.move(
                        to: CGPoint(
                            x: width * (-0.08 + progress * 0.16) + sway,
                            y: height * (0.05 + progress * 0.08)
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: width * (0.95 - progress * 0.08) + drift,
                            y: height * (0.36 + progress * 0.11)
                        ),
                        control1: CGPoint(
                            x: width * (0.30 + progress * 0.06) - sway,
                            y: height * (0.00 + progress * 0.16)
                        ),
                        control2: CGPoint(
                            x: width * (0.58 - progress * 0.10) + drift,
                            y: height * (0.50 + progress * 0.08)
                        )
                    )

                    layer.stroke(
                        path,
                        with: .color(Color.white.opacity(0.14 - Double(index) * 0.01)),
                        lineWidth: max(2, 12 - CGFloat(index))
                    )
                }
            }
        }
        .opacity(0.68)
    }
}

private struct FlowPaintSpeckleOverlay: View {
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            for index in 0..<240 {
                let normalizedX = CGFloat((index * 73) % 997) / 997
                let normalizedY = CGFloat((index * 151) % 991) / 991
                let driftX = CGFloat(sin(time * 0.06 + Double(index) * 0.3)) * 0.008
                let driftY = CGFloat(cos(time * 0.05 + Double(index) * 0.22)) * 0.006
                let x = size.width * min(max(normalizedX + driftX, 0), 1)
                let y = size.height * min(max(normalizedY + driftY, 0), 1)
                let diameter = CGFloat((index % 3) + 1)
                let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                let opacity = index.isMultiple(of: 5) ? 0.18 : 0.10
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(opacity))
                )
            }
        }
        .opacity(0.42)
    }
}
