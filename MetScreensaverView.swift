import ScreenSaver
import AppKit

// MARK: - Aspect-Fill + Panning Image View

private class ArtworkImageView: NSView {
    private let imageLayer = CALayer()
    var panDuration: TimeInterval = 18.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true   // triggers makeBackingLayer() when view enters a window
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    // Called by AppKit when the backing layer is first needed (guaranteed before rendering).
    // Safer than init: self.layer is nil until this runs.
    override func makeBackingLayer() -> CALayer {
        let backing = super.makeBackingLayer()
        backing.backgroundColor = NSColor.black.cgColor
        backing.masksToBounds   = true
        imageLayer.contentsGravity = .resize   // we size the sublayer manually
        backing.addSublayer(imageLayer)
        return backing
    }

    func display(image: NSImage?) {
        imageLayer.removeAllAnimations()

        guard let image,
              image.size.width > 0, image.size.height > 0,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageLayer.contents = nil
            return
        }

        let vs = bounds.size
        guard vs.width > 0, vs.height > 0 else { return }

        imageLayer.contents = cg
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        let imgA  = image.size.width / image.size.height
        let viewA = vs.width / vs.height

        let scaledW: CGFloat
        let scaledH: CGFloat
        if imgA > viewA {
            scaledH = vs.height
            scaledW = scaledH * imgA
        } else {
            scaledW = vs.width
            scaledH = scaledW / imgA
        }

        let excessW = max(0, scaledW - vs.width)
        let excessH = max(0, scaledH - vs.height)
        let minPan: CGFloat = 10.0

        // Determine start and end origins for the pan
        let sx: CGFloat, sy: CGFloat, ex: CGFloat, ey: CGFloat

        if imgA > viewA && excessW > minPan {
            // Wider image – pan horizontally
            let panLeft = Bool.random()
            sx = panLeft ? 0 : -excessW
            ex = panLeft ? -excessW : 0
            sy = 0; ey = 0
        } else if imgA <= viewA && excessH > minPan {
            // Taller image – pan vertically
            let panDown = Bool.random()
            sx = 0; ex = 0
            sy = panDown ? 0 : -excessH
            ey = panDown ? -excessH : 0
        } else {
            // Nearly square relative to viewport – center, no pan
            sx = (vs.width  - scaledW) / 2
            sy = (vs.height - scaledH) / 2
            ex = sx; ey = sy
        }

        // Place layer at start position without any implicit animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = CGRect(x: sx, y: sy, width: scaledW, height: scaledH)
        CATransaction.commit()

        guard sx != ex || sy != ey else { return }

        // Add explicit pan animation
        let startCenter = CGPoint(x: sx + scaledW / 2, y: sy + scaledH / 2)
        let endCenter   = CGPoint(x: ex + scaledW / 2, y: ey + scaledH / 2)

        let anim = CABasicAnimation(keyPath: "position")
        anim.fromValue = startCenter
        anim.toValue   = endCenter
        anim.duration  = panDuration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(anim, forKey: "pan")

        // Advance model to end so the layer stays put after the animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.position = endCenter
        CATransaction.commit()
    }
}

// MARK: - Screensaver View

@objc(MetScreensaverView)
class MetScreensaverView: ScreenSaverView {

    private static let slideInterval: TimeInterval = 20

    private var artworkView: ArtworkImageView!
    private var titleLabel: NSTextField!
    private var artistLabel: NSTextField!
    private var infoLabel: NSTextField!
    private var loadingLabel: NSTextField!
    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?

    // Next slide ready to display without waiting (main-thread only)
    private var preloadedArtwork: MetArtwork?
    private var preloadedImage: NSImage?

    // MARK: Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        buildUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildUI()
    }

    // MARK: Setup

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let scale: CGFloat = isPreview ? 0.42 : 1.0
        let pad: CGFloat   = 30 * scale

        // 1. Artwork view
        artworkView = ArtworkImageView(frame: bounds)
        artworkView.panDuration = MetScreensaverView.slideInterval - 2
        artworkView.autoresizingMask = [.width, .height]
        addSubview(artworkView)

        // 2. Labels
        titleLabel  = makeLabel(size: 20 * scale, alpha: 1.00, weight: .semibold, serif: true)
        artistLabel = makeLabel(size: 14 * scale, alpha: 0.85, weight: .regular,  serif: true)
        infoLabel   = makeLabel(size: 14 * scale, alpha: 0.60, weight: .regular,  serif: true)

        for lbl in [titleLabel!, artistLabel!, infoLabel!] { addSubview(lbl) }

        layoutText(padding: pad, scale: scale)

        // 3. Loading label – centered, visible until first image arrives
        loadingLabel = NSTextField()
        loadingLabel.stringValue     = "Loading artwork from The Met…"
        loadingLabel.alignment       = .center
        loadingLabel.textColor       = NSColor(white: 1, alpha: 0.5)
        loadingLabel.font            = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
        loadingLabel.isBordered      = false
        loadingLabel.isEditable      = false
        loadingLabel.drawsBackground = false
        loadingLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        loadingLabel.frame = NSRect(x: 0, y: bounds.midY - 10 * scale, width: bounds.width, height: 20 * scale)
        addSubview(loadingLabel)
    }

    private func makeLabel(size: CGFloat, alpha: CGFloat, weight: NSFont.Weight, serif: Bool) -> NSTextField {
        let tf = NSTextField()
        tf.isEditable       = false
        tf.isBordered       = false
        tf.drawsBackground  = false
        tf.textColor        = NSColor(white: 1, alpha: alpha)
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if serif, let descriptor = base.fontDescriptor.withDesign(.serif) {
            tf.font = NSFont(descriptor: descriptor, size: size) ?? base
        } else {
            tf.font = base
        }
        tf.maximumNumberOfLines          = 1
        tf.cell?.wraps                   = false
        tf.cell?.truncatesLastVisibleLine = true
        tf.cell?.lineBreakMode           = .byTruncatingTail
        tf.autoresizingMask              = [.width, .minYMargin]
        let shadow = NSShadow()
        shadow.shadowColor      = NSColor(white: 0, alpha: 0.7)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset     = NSSize(width: 0, height: -1)
        tf.shadow = shadow
        return tf
    }

    private func layoutText(padding: CGFloat, scale: CGFloat) {
        let w     = min(bounds.width - padding * 2, bounds.width / 3)
        let lineH = 28 * scale
        let gap   = 5  * scale

        infoLabel.frame   = NSRect(x: padding, y: padding,                        width: w, height: lineH)
        artistLabel.frame = NSRect(x: padding, y: padding + lineH + gap,          width: w, height: lineH)
        titleLabel.frame  = NSRect(x: padding, y: padding + (lineH + gap) * 2,    width: w, height: lineH * 1.5)
    }

    // MARK: ScreenSaverView

    override func startAnimation() {
        super.startAnimation()
        fetchAndDisplay()
        timer = Timer.scheduledTimer(
            timeInterval: MetScreensaverView.slideInterval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    override func stopAnimation() {
        super.stopAnimation()
        timer?.invalidate()
        timer = nil
        fetchTask?.cancel()
        fetchTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        preloadedArtwork = nil
        preloadedImage = nil
    }

    @objc private func timerFired() { fetchAndDisplay() }

    // MARK: Fetch & Display

    private func fetchAndDisplay() {
        fetchTask?.cancel()

        // If a prefetch already completed, display it instantly — no black screen
        if let artwork = preloadedArtwork {
            let image = preloadedImage
            preloadedArtwork = nil
            preloadedImage = nil
            present(artwork: artwork, image: image)
            startPrefetch()
            return
        }

        // Nothing preloaded yet (first slide, or prefetch lost the race) — show loading feedback
        loadingLabel.isHidden = false
        fetchTask = Task { [weak self] in
            guard let self else { return }
            guard let artwork = try? await MetAPI.shared.fetchRandomArtwork() else { return }
            guard !Task.isCancelled else { return }
            let image = await loadImage(from: artwork.imageURL)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.present(artwork: artwork, image: image)
                self.startPrefetch()
            }
        }
    }

    // Fetch the next slide in the background while the current one is visible.
    // Gives the full slideInterval (~20 s) to download, so the next slide is
    // ready before the timer fires.
    private func startPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            guard let artwork = try? await MetAPI.shared.fetchRandomArtwork() else { return }
            guard !Task.isCancelled else { return }
            let image = await self.loadImage(from: artwork.imageURL)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.preloadedArtwork = artwork
                self?.preloadedImage   = image
            }
        }
    }

    private func loadImage(from url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    // completionHandler is called on the main thread by AppKit
    @MainActor
    private func present(artwork: MetArtwork, image: NSImage?) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.5
            ctx.allowsImplicitAnimation = true
            artworkView.animator().alphaValue  = 0
            titleLabel.animator().alphaValue   = 0
            artistLabel.animator().alphaValue  = 0
            infoLabel.animator().alphaValue    = 0
        } completionHandler: { [weak self] in
            // AppKit always invokes this on the main thread
            MainActor.assumeIsolated {
                guard let self else { return }

                // Update content while everything is invisible
                self.artworkView.display(image: image)
                self.titleLabel.stringValue  = artwork.title
                self.artistLabel.stringValue = artwork.artist.isEmpty ? "Unknown Artist" : artwork.artist
                var parts: [String] = []
                if !artwork.date.isEmpty       { parts.append(artwork.date) }
                if !artwork.department.isEmpty { parts.append(artwork.department) }
                self.infoLabel.stringValue = parts.joined(separator: "  ·  ")

                // Hide loading label once we have real content
                self.loadingLabel.isHidden = true

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 1.5
                    ctx.allowsImplicitAnimation = true
                    self.artworkView.animator().alphaValue  = 1
                    self.titleLabel.animator().alphaValue   = 1
                    self.artistLabel.animator().alphaValue  = 1
                    self.infoLabel.animator().alphaValue    = 1
                }
            }
        }
    }
}
