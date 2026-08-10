import SwiftUI

struct IslandProgressVisual: Equatable, Sendable {
    let isVisible: Bool
    let fraction: Double?
    let animatesHighlight: Bool

    init(state: IslandState, reduceMotion: Bool) {
        switch state {
        case .preparing:
            isVisible = true
            fraction = nil
            animatesHighlight = !reduceMotion
        case let .converting(snapshot):
            isVisible = true
            fraction = min(max(snapshot.progress, 0), 1)
            animatesHighlight = !reduceMotion
        default:
            isVisible = false
            fraction = nil
            animatesHighlight = false
        }
    }
}

struct IslandProgressBorder: View {
    let visual: IslandProgressVisual
    let presentationMode: IslandPresentationMode

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !visual.animatesHighlight
            )
        ) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 72
            Group {
                if presentationMode == .physicalNotch {
                    border(TopAttachedIslandShape(), phase: phase)
                } else {
                    border(
                        RoundedRectangle(cornerRadius: 18, style: .continuous),
                        phase: phase
                    )
                }
            }
        }
        .padding(1.3)
        .opacity(visual.isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func border<S: Shape>(_ shape: S, phase: Double) -> some View {
        ZStack {
            shape.stroke(.cyan.opacity(0.16), lineWidth: 1)
            if let fraction = visual.fraction {
                shape
                    .trim(from: 0, to: fraction)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan, .blue, .white, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .shadow(color: .cyan.opacity(0.72), radius: 3)
                if visual.animatesHighlight, fraction > 0 {
                    shape
                        .trim(from: 0, to: fraction)
                        .stroke(
                            .white.opacity(0.9),
                            style: StrokeStyle(
                                lineWidth: 1.1,
                                lineCap: .round,
                                dash: [2, 42],
                                dashPhase: -phase
                            )
                        )
                }
            } else if visual.animatesHighlight {
                shape.stroke(
                    LinearGradient(
                        colors: [.clear, .cyan, .white, .blue, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: 2.1,
                        lineCap: .round,
                        dash: [18, 46],
                        dashPhase: -phase
                    )
                )
                .shadow(color: .cyan.opacity(0.65), radius: 3)
            } else {
                shape.stroke(.cyan.opacity(0.75), lineWidth: 1.6)
            }
        }
    }
}
