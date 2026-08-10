import AppKit

@MainActor
protocol StatusAnimationTimer: AnyObject {
    func invalidate()
}

@MainActor
final class StatusItemAnimator {
    typealias TimerFactory = @MainActor (
        _ interval: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any StatusAnimationTimer

    private let frames: [NSImage]
    private let reduceMotion: () -> Bool
    private let timerFactory: TimerFactory
    private let setImage: (NSImage) -> Void
    private var timer: (any StatusAnimationTimer)?
    private var intervalBucket: TimeInterval?
    private var frameIndex = 0

    private(set) var isAnimating = false

    init(
        frames: [NSImage] = StatusIconFrameRenderer.makeFrames(count: 8),
        reduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        timerFactory: @escaping TimerFactory = FoundationStatusAnimationTimer.make,
        setImage: @escaping (NSImage) -> Void
    ) {
        self.frames = frames
        self.reduceMotion = reduceMotion
        self.timerFactory = timerFactory
        self.setImage = setImage
    }

    func start(progress: Double) {
        guard let first = frames.first else {
            stop()
            return
        }
        guard let interval = StatusAnimationPolicy.frameInterval(
            progress: progress,
            reduceMotion: reduceMotion()
        ) else {
            stop()
            frameIndex = 0
            setImage(first)
            return
        }

        if !isAnimating {
            frameIndex = 0
            setImage(first)
        }
        isAnimating = true
        let bucket = (interval * 100).rounded() / 100
        guard intervalBucket != bucket else { return }
        timer?.invalidate()
        intervalBucket = bucket
        timer = timerFactory(bucket) { [weak self] in self?.advanceFrame() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        intervalBucket = nil
        frameIndex = 0
        isAnimating = false
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        setImage(frames[frameIndex])
    }
}

@MainActor
private final class FoundationStatusAnimationTimer: NSObject, StatusAnimationTimer {
    private let action: @MainActor () -> Void
    private var timer: Timer?

    private init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.action = action
        super.init()
        timer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(fire),
            userInfo: nil,
            repeats: true
        )
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    static func make(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any StatusAnimationTimer {
        FoundationStatusAnimationTimer(interval: interval, action: action)
    }

    @objc private func fire() { action() }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}

enum StatusIconFrameRenderer {
    static func makeFrames(count: Int) -> [NSImage] {
        guard count > 0 else { return [] }
        return (0..<count).map { highlightedIndex in
            let image = NSImage(size: NSSize(width: 18, height: 18))
            image.lockFocus()
            NSColor.labelColor.setFill()

            let center = CGPoint(x: 9, y: 9)
            let radius: CGFloat = 6.1
            for index in 0..<count {
                let angle = (Double(index) / Double(count)) * Double.pi * 2
                    - Double.pi / 2
                let point = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                let diameter: CGFloat = index == highlightedIndex ? 3.2 : 1.7
                NSBezierPath(
                    ovalIn: CGRect(
                        x: point.x - diameter / 2,
                        y: point.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                ).fill()
            }

            let arrow = NSBezierPath()
            NSColor.labelColor.setStroke()
            arrow.lineWidth = 1.5
            arrow.lineCapStyle = .round
            arrow.move(to: CGPoint(x: 9, y: 12))
            arrow.line(to: CGPoint(x: 9, y: 6.8))
            arrow.move(to: CGPoint(x: 6.8, y: 8.8))
            arrow.line(to: CGPoint(x: 9, y: 6.5))
            arrow.line(to: CGPoint(x: 11.2, y: 8.8))
            arrow.stroke()

            image.unlockFocus()
            image.isTemplate = true
            image.accessibilityDescription = "File Island is converting"
            return image
        }
    }
}
