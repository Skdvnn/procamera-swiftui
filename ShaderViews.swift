import SwiftUI

// MARK: - Film Grain Overlay using Metal Shader
struct FilmGrainShaderView: View {
    let intensity: CGFloat
    @State private var time: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            Rectangle()
                .fill(.clear)
                .colorEffect(
                    ShaderLibrary.filmGrain(
                        .float(elapsed),
                        .float(intensity),
                        .float(400)
                    )
                )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Frosted Glass Background
struct FrostedGlassView<Content: View>: View {
    let cornerRadius: CGFloat
    let blurRadius: CGFloat
    let tint: Color
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 16,
        blurRadius: CGFloat = 10,
        tint: Color = .white.opacity(0.1),
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.blurRadius = blurRadius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .background(
                ZStack {
                    // Base blur
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // Tint overlay
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(tint)

                    // Noise texture for frosted effect
                    GrainTextureView(density: 0.02, opacity: 0.08)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                    // Edge highlight
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .white.opacity(0.1),
                                    .white.opacity(0.05),
                                    .white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
    }
}

// MARK: - Grain Texture View (Canvas-based for compatibility)
struct GrainTextureView: View {
    let density: CGFloat
    let opacity: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            Canvas { context, size in
                let count = Int(size.width * size.height * density)
                for _ in 0..<count {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let alpha = CGFloat.random(in: 0.02...opacity)
                    let dotSize = CGFloat.random(in: 0.5...1.5)

                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(.white.opacity(alpha))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Heavy Film Grain (for camera preview)
struct HeavyFilmGrain: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            Canvas { context, size in
                // Coarse grain
                for _ in 0..<Int(size.width * size.height * 0.012) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let alpha = CGFloat.random(in: 0.02...0.15)
                    let dotSize = CGFloat.random(in: 0.8...2.5)

                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(.white.opacity(alpha))
                    )
                }

                // Fine grain
                for _ in 0..<Int(size.width * size.height * 0.005) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let alpha = CGFloat.random(in: 0.05...0.2)

                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(.black.opacity(alpha))
                    )
                }
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

// MARK: - Metallic Button Style
struct MetallicButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Shadow
            Circle()
                .fill(Color.black.opacity(0.5))
                .blur(radius: 4)
                .offset(y: 2)

            // Base gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.5),
                            Color(white: 0.3),
                            Color(white: 0.35),
                            Color(white: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .padding(3)

            // Border
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )

            // Content
            configuration.label
                .foregroundColor(Color(white: 0.15))

            // Press effect
            if configuration.isPressed {
                Circle()
                    .fill(Color.black.opacity(0.2))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Dark Metallic Button Style
struct DarkMetallicButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Base
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.2),
                            Color(white: 0.12),
                            Color(white: 0.08)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size
                    )
                )

            // Subtle highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .padding(2)

            // Border
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)

            // Content
            configuration.label

            if configuration.isPressed {
                Circle()
                    .fill(Color.white.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Glass Panel Modifier
struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.05))

                    // Grain texture
                    GrainTextureView(density: 0.015, opacity: 0.06)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                    // Border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.4),
                                    .white.opacity(0.1),
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Metal Shutter Button Surface
struct MetalShutterSurface: View {
    let size: CGFloat
    let isPressed: Bool

    @State private var pressAmount: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .colorEffect(
                ShaderLibrary.shutterButtonMetal(
                    .float2(size, size),
                    .float(pressAmount)
                )
            )
            .onChange(of: isPressed) { _, newValue in
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    pressAmount = newValue ? 1.0 : 0.0
                }
            }
    }
}

// MARK: - Leica Vulcanite Texture (Metal Shader)
struct LeicaVulcaniteTexture: View {
    let scale: CGFloat
    let intensity: CGFloat

    init(scale: CGFloat = 400, intensity: CGFloat = 1.0) {
        self.scale = scale
        self.intensity = intensity
    }

    var body: some View {
        Rectangle()
            .fill(Color(white: 0.075))  // Dark vulcanite base
            .colorEffect(
                ShaderLibrary.vulcaniteTexture(
                    .float(scale),
                    .float(intensity)
                )
            )
            .allowsHitTesting(false)
    }
}
