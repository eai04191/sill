import AppKit
import Combine
import SwiftUI

// MARK: - Image Cache

/// A singleton cache for storing downloaded NSImage objects.
///
/// The now playing artwork is written to a new file for each track, so an entry is only looked up again while its
/// track plays; without a limit, the entries of past tracks piled up, about 4 MB for each popup-sized artwork. The
/// limit keeps the current track's sizes, for the bar and the popup, and a few recent ones.
final class ImageCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 8
        return cache
    }()
}

// MARK: - Image Loader

/// An observable object that asynchronously downloads and caches images.
final class ImageLoader: ObservableObject {
    @Published var image: NSImage?
    
    private var cancellable: AnyCancellable?
    
    /// The URL of the image to load.
    var url: URL?
    
    /// Optional target size to which the image should be resized.
    var targetSize: CGSize?
    
    /// Initializes the loader with an optional URL and target size.
    /// - Parameters:
    ///   - url: The URL of the image.
    ///   - targetSize: The desired size for the image.
    init(url: URL?, targetSize: CGSize? = nil) {
        self.url = url
        self.targetSize = targetSize
    }
    
    /// Generates a cache key based on the URL and target size.
    private var cacheKey: NSString? {
        guard let url = url else { return nil }
        if let targetSize = targetSize {
            return "\(url.absoluteString)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        } else {
            return url.absoluteString as NSString
        }
    }
    
    /// Loads the image from the URL, resizing if needed, and caches it.
    func load() {
        // Cancel any ongoing request before starting a new one.
        cancellable?.cancel()
        
        // Without a URL there is no image, rather than the previous URL's.
        guard let url = url, let key = cacheKey else {
            image = nil
            return
        }
        
        // Check for cached image.
        if let cachedImage = ImageCache.shared.object(forKey: key) {
            self.image = cachedImage
            return
        }
        
        // Download image asynchronously.
        cancellable = URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { [weak self] data, _ -> NSImage? in
                guard let downloadedImage = NSImage(data: data) else { return nil }
                if let targetSize = self?.targetSize {
                    return downloadedImage.resized(to: targetSize) ?? downloadedImage
                }
                return downloadedImage
            }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] downloadedImage in
                if let downloadedImage = downloadedImage {
                    ImageCache.shared.setObject(downloadedImage, forKey: key)
                }
                self?.image = downloadedImage
            }
    }
    
    deinit {
        cancellable?.cancel()
    }
}

// MARK: - NSImage Extension

extension NSImage {
    /// Returns the image scaled to fill the target size, cropping the overflow at the center, so that artwork of
    /// another aspect ratio, such as a 16:9 video thumbnail, is not squashed.
    /// Drawn with Core Graphics, as ImageLoader resizes off the main thread where lockFocus is not safe.
    /// - Parameter newSize: The target size in points.
    /// - Returns: A new NSImage of the given size, or nil if resizing fails.
    func resized(to newSize: NSSize) -> NSImage? {
        // Rendered at 2x, so the image stays sharp on Retina displays.
        let scale: CGFloat = 2
        let pixelWidth = Int((newSize.width * scale).rounded())
        let pixelHeight = Int((newSize.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
            let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        let fill = max(
            CGFloat(pixelWidth) / CGFloat(cgImage.width), CGFloat(pixelHeight) / CGFloat(cgImage.height))
        let drawWidth = CGFloat(cgImage.width) * fill
        let drawHeight = CGFloat(cgImage.height) * fill
        context.interpolationQuality = .high
        context.draw(
            cgImage,
            in: CGRect(
                x: (CGFloat(pixelWidth) - drawWidth) / 2, y: (CGFloat(pixelHeight) - drawHeight) / 2,
                width: drawWidth, height: drawHeight))
        guard let resized = context.makeImage() else { return nil }
        return NSImage(cgImage: resized, size: newSize)
    }
}

// MARK: - Rotate Animated Cached Image View

/// A view that displays a cached image with a rotation and blur animation when the image changes, or replaces it at
/// once with Reduce Motion, which asks to avoid flipping and blurring (HIG, Motion).
struct RotateAnimatedCachedImage<RotatingContent: View>: View {
    let url: URL?
    let targetSize: CGSize?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @StateObject private var loader: ImageLoader
    @State private var displayedImage: NSImage?
    @State private var rotation: Double = 1
    let rotatingModifier: (Image) -> RotatingContent
    
    /// Initializes the view with a URL, optional target size, and a custom rotating modifier.
    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder rotatingModifier: @escaping (Image) -> RotatingContent
    ) {
        self.url = url
        self.targetSize = targetSize
        _loader = StateObject(wrappedValue: ImageLoader(url: url, targetSize: targetSize))
        self.rotatingModifier = rotatingModifier
    }
    
    /// Convenience initializer when no custom modifier is needed.
    init(url: URL?, targetSize: CGSize? = nil) where RotatingContent == Image {
        self.init(url: url, targetSize: targetSize) { image in image }
    }
    
    var body: some View {
        Group {
            if let image = displayedImage {
                rotatingModifier(Image(nsImage: image).resizable())
                    .blur(radius: abs(1 - rotation) * 5)
                    .scaleEffect(x: rotation)
            } else {
                Color.clear
            }
        }
        .onAppear { loader.load() }
        .onReceive(loader.$image) { newImage in
            guard let newImage = newImage else {
                displayedImage = nil
                return
            }
            // If image is loading for the first time.
            if displayedImage == nil || reduceMotion {
                displayedImage = newImage
            } else if displayedImage != newImage {
                // Animate the transition.
                withAnimation(.easeInOut(duration: 0.2)) { rotation = 0 }
                withAnimation(.easeOut(duration: 0.3).delay(0.2)) { rotation = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    displayedImage = newImage
                }
            }
        }
        .onChange(of: url) { _, newURL in
            loader.url = newURL
            loader.load()
        }
    }
}

// MARK: - Fade Animated Cached Image View

/// A view that displays a cached image with a fade transition when the image changes.
struct FadeAnimatedCachedImage<Content: View>: View {
    let url: URL?
    let targetSize: CGSize?
    
    @StateObject private var loader: ImageLoader
    @State private var currentImage: NSImage?
    @State private var nextImage: NSImage?
    @State private var showNextImage: Bool = false
    let content: (Image) -> Content
    
    /// Initializes the view with a URL, optional target size, and a custom content modifier.
    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.url = url
        self.targetSize = targetSize
        _loader = StateObject(wrappedValue: ImageLoader(url: url, targetSize: targetSize))
        self.content = content
    }
    
    /// Convenience initializer when no custom modifier is needed.
    init(url: URL?, targetSize: CGSize? = nil) where Content == Image {
        self.init(url: url, targetSize: targetSize) { image in image }
    }
    
    var body: some View {
        ZStack {
            if let currentImage = currentImage {
                content(Image(nsImage: currentImage))
            }
            
            if let nextImage = nextImage {
                content(Image(nsImage: nextImage))
                    .opacity(showNextImage ? 1 : 0)
            }
        }
        .onAppear { loader.load() }
        .onReceive(loader.$image) { newImage in
            guard let newImage = newImage else {
                currentImage = nil
                nextImage = nil
                showNextImage = false
                return
            }
            // Set the image for the first time.
            if currentImage == nil {
                currentImage = newImage
            } else if currentImage != newImage {
                // Animate the fade transition.
                nextImage = newImage
                withAnimation(.easeInOut(duration: 0.5)) {
                    showNextImage = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    currentImage = newImage
                    nextImage = nil
                    showNextImage = false
                }
            }
        }
        .onChange(of: url) { _, newURL in
            loader.url = newURL
            loader.load()
        }
    }
}
