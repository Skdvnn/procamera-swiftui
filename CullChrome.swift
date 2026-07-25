import SwiftUI

// MARK: - Cull progress rail (amber kept / safelight out / open dim)

struct CullProgressRail: View {
    let kept: Int
    let rejected: Int
    let unmarked: Int
    var height: CGFloat = 3

    private var total: CGFloat {
        CGFloat(max(1, kept + rejected + unmarked))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 1) {
                if kept > 0 {
                    Capsule(style: .continuous)
                        .fill(CullPalette.amber)
                        .frame(width: max(2, w * CGFloat(kept) / total - 1))
                }
                if rejected > 0 {
                    Capsule(style: .continuous)
                        .fill(CullPalette.safelight.opacity(0.85))
                        .frame(width: max(2, w * CGFloat(rejected) / total - 1))
                }
                if unmarked > 0 {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: max(2, w * CGFloat(unmarked) / total - 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .animation(CullMotion.settle, value: kept)
        .animation(CullMotion.settle, value: rejected)
        .animation(CullMotion.settle, value: unmarked)
    }
}

// MARK: - Film sprocket edge

struct FilmSprocketEdge: View {
    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.4)
                    )
                    .frame(width: 7, height: 5)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(Color(hex: "1a1612"))
    }
}

// MARK: - First-run thumb coach

struct ThumbZoneCoach: View {
    @Binding var visible: Bool

    var body: some View {
        if visible {
            VStack(spacing: 8) {
                Spacer()
                ZStack {
                    // Soft zone plate
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            CullPalette.amber.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(CullPalette.amber.opacity(0.06))
                        )
                        .frame(height: 120)
                        .padding(.horizontal, 28)

                    VStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(CullPalette.amber.opacity(0.8))
                        Text("SWIPE HERE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(CullPalette.amber.opacity(0.85))
                        Text("↑ keep   ↓ reject")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(.bottom, 150)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .allowsHitTesting(false)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    withAnimation(CullMotion.settle) { visible = false }
                }
            }
        }
    }
}

// MARK: - Edge peeks (prev / next frame ghosts while scrubbing)

struct EdgePeekFrames: View {
    let prev: UIImage?
    let next: UIImage?
    let dragX: CGFloat
    let size: CGSize

    var body: some View {
        ZStack {
            if let prev, dragX > 12 {
                peek(image: prev, leading: true, amount: min(1, dragX / 90))
            }
            if let next, dragX < -12 {
                peek(image: next, leading: false, amount: min(1, -dragX / 90))
            }
        }
        .allowsHitTesting(false)
    }

    private func peek(image: UIImage, leading: Bool, amount: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .opacity(0.35 * Double(amount))
            .scaleEffect(0.92 + 0.04 * amount)
            .offset(x: leading ? -size.width * 0.72 + dragX * 0.15 : size.width * 0.72 + dragX * 0.15)
            .blur(radius: 0.5)
    }
}

// MARK: - Compare (two frames, synced zoom)

// MARK: - Compare (two frames, synced zoom)

struct CompareFramesView: View {
    let store: GalleryStore
    let left: ShotMetadata
    let right: ShotMetadata
    let onKeepLeft: () -> Void
    let onKeepRight: () -> Void
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            DarkroomGround(intensity: 0.9)

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        DarkroomIconButton(systemName: "xmark")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("COMPARE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(2.5)
                            .foregroundColor(CullPalette.amber.opacity(0.75))
                        Text("Pinch · double-tap reset · KEEP A/B below")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Text("SKIP")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(CullPalette.hairline, lineWidth: 0.6)
                            )
                    }
                    .accessibilityLabel("Skip compare without marking")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                GeometryReader { geo in
                    let landscape = geo.size.width > geo.size.height
                    let stack = landscape
                        ? AnyLayout(HStackLayout(spacing: 2))
                        : AnyLayout(VStackLayout(spacing: 2))

                    stack {
                        pane(shot: left, label: "A")
                        pane(shot: right, label: "B")
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        withAnimation(CullMotion.flick) {
                            scale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        }
                        Haptics.light()
                    }
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(lastScale * value, 1.0), 5.0)
                                }
                                .onEnded { _ in lastScale = scale },
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1.01 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                    if scale <= 1.01 {
                                        withAnimation(CullMotion.flick) {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                    )
                }

                // Explicit keep chrome — pane taps used to steal double-tap reset.
                HStack(spacing: 12) {
                    Button(action: onKeepLeft) {
                        Text("KEEP A")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundColor(CullPalette.amber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(CullPalette.amber.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(CullPalette.amber.opacity(0.55), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Keep frame A")

                    Button(action: onKeepRight) {
                        Text("KEEP B")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundColor(CullPalette.amber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(CullPalette.amber.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(CullPalette.amber.opacity(0.55), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Keep frame B")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Text("ZOOM & PAN ARE LOCKED TOGETHER")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.28))
                    .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private func pane(shot: ShotMetadata, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let img = store.image(for: shot) ?? store.thumbnail(for: shot) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CullPalette.amber)
                Text(metaLine(for: shot))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            .padding(8)
            .background(Color.black.opacity(0.5))
        }
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(CullPalette.hairline, lineWidth: 0.6)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frame \(label), \(metaLine(for: shot))")
    }

    private func metaLine(for shot: ShotMetadata) -> String {
        var parts: [String] = []
        parts.append("ISO \(shot.iso)")
        parts.append(shot.shutter)
        if shot.aperture > 0 {
            parts.append(String(format: "ƒ%.1f", shot.aperture))
        }
        if shot.filmFilter != "None", !shot.filmFilter.isEmpty {
            parts.append(shot.filmFilter)
        }
        if shot.lensFX != "None", !shot.lensFX.isEmpty {
            parts.append(shot.lensFX)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Contact sheet loupe overlay

struct SheetLoupeOverlay: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.82 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(20)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
                .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
                .overlay(alignment: .topTrailing) {
                    Button(action: dismiss) {
                        DarkroomIconButton(systemName: "xmark")
                    }
                    .padding(24)
                }
        }
        .onAppear {
            withAnimation(CullMotion.loupeIn) { appeared = true }
        }
    }

    private func dismiss() {
        withAnimation(CullMotion.loupeOut) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: onDismiss)
    }
}
