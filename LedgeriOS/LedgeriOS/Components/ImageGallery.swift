import SwiftUI

struct ImageGallery: View {
    let images: [AttachmentRef]
    var initialIndex: Int = 0
    @Binding var isPresented: Bool

    @State private var currentIndex: Int = 0
    @State private var controlsVisible: Bool = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var currentZoom: CGFloat = 1.0

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0
    private let zoomStep: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }

            TabView(selection: $currentIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, attachment in
                    ZoomableImage(url: URL(string: attachment.url), externalZoom: zoomBindingFor(index))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: currentIndex) { _, _ in
                currentZoom = 1.0
                resetHideTimer()
            }

            // Controls overlay
            controlsOverlay
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: controlsVisible)
                .allowsHitTesting(controlsVisible)
        }
        .statusBarHidden()
        .onAppear {
            currentIndex = initialIndex
            resetHideTimer()
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
    }

    // MARK: - Zoom Binding

    private func zoomBindingFor(_ index: Int) -> Binding<CGFloat> {
        Binding(
            get: { index == currentIndex ? currentZoom : 1.0 },
            set: { newValue in
                if index == currentIndex {
                    currentZoom = newValue
                    resetHideTimer()
                }
            }
        )
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            // Top bar
            VStack {
                HStack {
                    closeButton
                    Spacer()
                    shareButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }

            // Bottom area
            VStack {
                Spacer()

                if MediaGalleryCalculations.shouldShowResetZoom(currentZoom: currentZoom) || true {
                    zoomControls
                        .padding(.bottom, Spacing.sm)
                }

                infoBar
            }
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        if currentIndex < images.count, let url = URL(string: images[currentIndex].url) {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        HStack(spacing: Spacing.md) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    currentZoom = MediaGalleryCalculations.previousZoom(current: currentZoom, step: zoomStep, min: minZoom)
                }
                resetHideTimer()
            } label: {
                zoomButtonLabel(systemName: "minus")
            }
            .disabled(!MediaGalleryCalculations.canZoomOut(currentZoom: currentZoom, minZoom: minZoom))

            if MediaGalleryCalculations.shouldShowResetZoom(currentZoom: currentZoom) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        currentZoom = 1.0
                    }
                    resetHideTimer()
                } label: {
                    zoomButtonLabel(systemName: "arrow.counterclockwise")
                }
            }

            Button {
                withAnimation(.spring(response: 0.3)) {
                    currentZoom = MediaGalleryCalculations.nextZoom(current: currentZoom, step: zoomStep, max: maxZoom)
                }
                resetHideTimer()
            } label: {
                zoomButtonLabel(systemName: "plus")
            }
            .disabled(!MediaGalleryCalculations.canZoomIn(currentZoom: currentZoom, maxZoom: maxZoom))
        }
    }

    private func zoomButtonLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.black.opacity(0.5))
            .clipShape(Circle())
    }

    // MARK: - Info Bar

    private var infoBar: some View {
        VStack(spacing: 2) {
            if images.count > 1 {
                Text(MediaGalleryCalculations.imageCounterLabel(currentIndex: currentIndex, total: images.count))
                    .font(Typography.small)
                    .foregroundStyle(.white)
            }

            if let fileName = currentIndex < images.count ? images[currentIndex].fileName : nil {
                Text(fileName)
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.7))
    }

    // MARK: - Auto-Hide Controls

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            resetHideTimer()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func resetHideTimer() {
        hideControlsTask?.cancel()
        guard currentZoom <= 1.01 else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible = false
                }
            }
        }
    }
}

// MARK: - ZoomableImage

private struct ZoomableImage: View {
    let url: URL?
    @Binding var externalZoom: CGFloat

    @State private var steadyStateScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private var currentScale: CGFloat {
        min(max(steadyStateScale * gestureScale, 1), 4)
    }

    private var currentOffset: CGSize {
        CGSize(
            width: offset.width + dragOffset.width,
            height: offset.height + dragOffset.height
        )
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                placeholderView(systemName: "exclamationmark.triangle")
            case .empty:
                ProgressView()
                    .tint(.white)
            @unknown default:
                placeholderView(systemName: "photo")
            }
        }
        .scaleEffect(currentScale)
        .offset(currentOffset)
        .gesture(magnificationGesture)
        .gesture(dragGesture)
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3)) {
                if steadyStateScale > 1.01 {
                    steadyStateScale = 1.0
                    offset = .zero
                } else {
                    steadyStateScale = 2.0
                }
                externalZoom = steadyStateScale
            }
        }
        .onChange(of: externalZoom) { _, newValue in
            // External zoom change (from parent zoom buttons)
            if abs(newValue - steadyStateScale) > 0.01 {
                withAnimation(.spring(response: 0.3)) {
                    steadyStateScale = newValue
                    if steadyStateScale <= 1.01 {
                        offset = .zero
                    }
                }
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = steadyStateScale * value
                steadyStateScale = min(max(newScale, 1), 4)
                if steadyStateScale <= 1.01 {
                    offset = .zero
                }
                externalZoom = steadyStateScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                if steadyStateScale > 1.01 {
                    state = value.translation
                }
            }
            .onEnded { value in
                if steadyStateScale > 1.01 {
                    offset = CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )
                }
            }
    }

    @ViewBuilder
    private func placeholderView(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.largeTitle)
            .foregroundStyle(.white.opacity(0.5))
    }
}

// MARK: - Previews

#Preview("Single Image") {
    ImageGallery(
        images: [AttachmentRef(url: "https://picsum.photos/800/600", kind: .image)],
        isPresented: .constant(true)
    )
}

#Preview("Multiple Images") {
    ImageGallery(
        images: [
            AttachmentRef(url: "https://picsum.photos/800/600", kind: .image, fileName: "living-room.jpg"),
            AttachmentRef(url: "https://picsum.photos/600/800", kind: .image, fileName: "bedroom.jpg"),
            AttachmentRef(url: "https://picsum.photos/700/700", kind: .image),
        ],
        initialIndex: 1,
        isPresented: .constant(true)
    )
}
