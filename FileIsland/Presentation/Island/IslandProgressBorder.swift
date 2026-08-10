import SwiftUI

enum IslandProgressStyle: Equatable, Sendable {
    case hidden
    case indeterminate
    case determinate(Double)
}

struct IslandProgressVisual: Equatable, Sendable {
    let style: IslandProgressStyle
    let animatesComet: Bool

    init(state: IslandState, reduceMotion: Bool) {
        switch state {
        case .preparing:
            style = .indeterminate
            animatesComet = !reduceMotion
        case let .converting(snapshot):
            style = .determinate(min(max(snapshot.progress, 0), 1))
            animatesComet = false
        default:
            style = .hidden
            animatesComet = false
        }
    }
}

struct IslandProgressBorder: View {
    let visual: IslandProgressVisual
    let presentationMode: IslandPresentationMode

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 60.0, paused: !visual.animatesComet)
        ) { context in
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - horizontalInset * 2)
                let phase = normalizedPhase(at: context.date)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    edgeTrack(width: width, phase: phase)
                        .frame(width: width, height: 4)
                        .mask(Capsule())
                        .padding(.bottom, bottomInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(visual.style == .hidden ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var horizontalInset: CGFloat {
        presentationMode == .physicalNotch ? 24 : 14
    }

    private var bottomInset: CGFloat {
        presentationMode == .physicalNotch ? 1.5 : 2.5
    }

    private func normalizedPhase(at date: Date) -> Double {
        let cycle = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.6)
        return cycle / 1.6
    }

    @ViewBuilder
    private func edgeTrack(width: CGFloat, phase: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.055))
                .frame(height: 1)

            switch visual.style {
            case .hidden:
                EmptyView()
            case .indeterminate where visual.animatesComet:
                let cometWidth = min(54, width * 0.22)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.accentColor.opacity(0.32),
                                .white.opacity(0.88),
                                Color.accentColor.opacity(0.16),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: cometWidth, height: 1.5)
                    .shadow(color: Color.accentColor.opacity(0.22), radius: 1.5)
                    .offset(x: (width + cometWidth) * phase - cometWidth)
            case .indeterminate:
                Capsule()
                    .fill(Color.accentColor.opacity(0.28))
                    .frame(height: 1.25)
            case let .determinate(fraction):
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.38),
                                Color.accentColor.opacity(0.78),
                                .white.opacity(0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width, height: 1.5)
                    .scaleEffect(x: fraction, anchor: .leading)
                    .shadow(color: Color.accentColor.opacity(0.18), radius: 1.25)
            }
        }
    }
}
