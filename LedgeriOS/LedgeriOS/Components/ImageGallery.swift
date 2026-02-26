import SwiftUI

struct ImageGallery: View {
    let images: [AttachmentRef]
    var initialIndex: Int = 0
    @Binding var isPresented: Bool
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, attachment in
                    ZoomableImage(url: URL(string: attachment.url))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            closeButton
        }
        .statusBarHidden()
        .onAppear {
            currentIndex = initialIndex
        }
    }

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
        .padding()
    }
}

// MARK: - ZoomableImage

private struct ZoomableImage: View {
    let url: URL?

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

// MARK: - Reset zoom on page change

extension ImageGallery {
    // Note: ZoomableImage manages its own state per-instance via TabView recreation
}

#Preview("Single Image") {
    ImageGallery(
        images: [AttachmentRef(url: "https://picsum.photos/800/600", kind: .image)],
        isPresented: .constant(true)
    )
}

#Preview("Multiple Images") {
    ImageGallery(
        images: [
            AttachmentRef(url: "https://picsum.photos/800/600", kind: .image),
            AttachmentRef(url: "https://picsum.photos/600/800", kind: .image),
            AttachmentRef(url: "https://picsum.photos/700/700", kind: .image),
        ],
        initialIndex: 1,
        isPresented: .constant(true)
    )
}
