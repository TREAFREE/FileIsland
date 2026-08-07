import AppKit

@MainActor
struct IslandScreenProvider {
    func targetScreen(for point: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        NSScreen.screens.first { screen in
            NSMouseInRect(point, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func presentationMode(for screen: NSScreen) -> IslandPresentationMode {
        geometry(for: screen).physicalNotchFrame != nil
            ? .physicalNotch
            : .floatingPill
    }

    func geometry(for screen: NSScreen) -> IslandScreenGeometry {
        IslandScreenGeometry(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }
}
