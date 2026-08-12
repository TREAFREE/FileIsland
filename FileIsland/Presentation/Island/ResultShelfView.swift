import AppKit
import SwiftUI

struct ResultShelfView: NSViewRepresentable {
    let outputURLs: [URL]
    let copyTitle: String
    let revealTitle: String
    let selectAllTitle: String
    let dragHelp: String
    let missingHelp: String
    let onReveal: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ResultShelfScrollView {
        let scrollView = ResultShelfScrollView()
        let collectionView = ResultShelfCollectionView()
        let layout = NSCollectionViewFlowLayout()

        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(
            width: ResultShelfLayoutMetrics.itemWidth,
            height: ResultShelfLayoutMetrics.itemHeight
        )
        layout.minimumInteritemSpacing = ResultShelfLayoutMetrics.itemSpacing
        layout.minimumLineSpacing = ResultShelfLayoutMetrics.itemSpacing

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            ResultShelfCollectionItem.self,
            forItemWithIdentifier: ResultShelfCollectionItem.identifier
        )
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: true)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = collectionView

        context.coordinator.collectionView = collectionView
        context.coordinator.scrollView = scrollView
        context.coordinator.configureCommandHandlers()
        scrollView.onLayout = { [weak coordinator = context.coordinator] width in
            coordinator?.updateLayout(viewportWidth: width)
        }
        context.coordinator.reloadIfNeeded(force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: ResultShelfScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configureCommandHandlers()
        context.coordinator.reloadIfNeeded(force: false)
        context.coordinator.updateLayout(viewportWidth: scrollView.contentView.bounds.width)
    }

    static func dismantleNSView(
        _ scrollView: ResultShelfScrollView,
        coordinator: Coordinator
    ) {
        coordinator.cancelThumbnailTasks()
        scrollView.onLayout = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: ResultShelfView
        weak var collectionView: ResultShelfCollectionView?
        weak var scrollView: ResultShelfScrollView?

        private var renderedURLs: [URL] = []
        private var thumbnailTasks: [URL: Task<Void, Never>] = [:]
        private let thumbnailCache = NSCache<NSURL, NSImage>()
        private let thumbnailLoader: any ThumbnailLoading = QuickLookThumbnailLoader()

        init(parent: ResultShelfView) {
            self.parent = parent
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

        func collectionView(
            _ collectionView: NSCollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            renderedURLs.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            guard let item = collectionView.makeItem(
                withIdentifier: ResultShelfCollectionItem.identifier,
                for: indexPath
            ) as? ResultShelfCollectionItem,
                renderedURLs.indices.contains(indexPath.item)
            else {
                return NSCollectionViewItem()
            }

            let url = renderedURLs[indexPath.item]
            let isAvailable = ResultShelfDragPayload.eligibleURL(
                at: indexPath.item,
                outputURLs: renderedURLs
            ) != nil
            let fallback = fallbackImage(for: url, isAvailable: isAvailable)
            item.configure(
                url: url,
                image: thumbnailCache.object(forKey: url as NSURL) ?? fallback,
                isAvailable: isAvailable,
                dragHelp: parent.dragHelp,
                missingHelp: parent.missingHelp
            )
            requestThumbnail(for: url, item: item, isAvailable: isAvailable)
            return item
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            pasteboardWriterForItemAt indexPath: IndexPath
        ) -> (any NSPasteboardWriting)? {
            guard let url = ResultShelfDragPayload.eligibleURL(
                at: indexPath.item,
                outputURLs: renderedURLs
            ) else { return nil }
            return url as NSURL
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            canDragItemsAt indexPaths: Set<IndexPath>,
            with event: NSEvent
        ) -> Bool {
            !indexPaths.isEmpty && indexPaths.allSatisfy {
                ResultShelfDragPayload.eligibleURL(
                    at: $0.item,
                    outputURLs: renderedURLs
                ) != nil
            }
        }

        func reloadIfNeeded(force: Bool) {
            guard force || renderedURLs != parent.outputURLs else { return }
            renderedURLs = parent.outputURLs
            thumbnailTasks.values.forEach { $0.cancel() }
            thumbnailTasks.removeAll()
            collectionView?.deselectAll(nil)
            collectionView?.reloadData()
            updateLayout(viewportWidth: scrollView?.contentView.bounds.width ?? 0)
        }

        func configureCommandHandlers() {
            collectionView?.copyTitle = parent.copyTitle
            collectionView?.revealTitle = parent.revealTitle
            collectionView?.selectAllTitle = parent.selectAllTitle
            collectionView?.copyHandler = { [weak self] in self?.copySelection() }
            collectionView?.revealHandler = { [weak self] in self?.revealSelection() }
            collectionView?.dragURLProvider = { [weak self] clickedIndex, selectedIndexes in
                guard let self else { return [] }
                return ResultShelfDragPayload.urls(
                    clickedIndex: clickedIndex,
                    selectedIndexes: selectedIndexes,
                    outputURLs: renderedURLs
                )
            }
        }

        func updateLayout(viewportWidth: CGFloat) {
            guard viewportWidth > 0,
                let collectionView,
                let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout
            else { return }

            let leading = ResultShelfLayoutMetrics.leadingInset(
                viewportWidth: viewportWidth,
                itemCount: renderedURLs.count
            )
            let overflows = ResultShelfLayoutMetrics.overflows(
                viewportWidth: viewportWidth,
                itemCount: renderedURLs.count
            )
            let trailing = overflows ? ResultShelfLayoutMetrics.minimumHorizontalInset : leading
            let insets = NSEdgeInsets(top: 0, left: leading, bottom: 0, right: trailing)

            if !Self.matches(layout.sectionInset, insets) {
                layout.sectionInset = insets
                layout.invalidateLayout()
            }
            scrollView?.hasHorizontalScroller = overflows
        }

        private static func matches(_ lhs: NSEdgeInsets, _ rhs: NSEdgeInsets) -> Bool {
            lhs.top == rhs.top
                && lhs.left == rhs.left
                && lhs.bottom == rhs.bottom
                && lhs.right == rhs.right
        }

        func cancelThumbnailTasks() {
            thumbnailTasks.values.forEach { $0.cancel() }
            thumbnailTasks.removeAll()
        }

        private func requestThumbnail(
            for url: URL,
            item: ResultShelfCollectionItem,
            isAvailable: Bool
        ) {
            guard isAvailable,
                thumbnailCache.object(forKey: url as NSURL) == nil,
                thumbnailTasks[url] == nil
            else { return }

            thumbnailTasks[url] = Task { [weak self, weak item] in
                guard let self else { return }
                let image = await thumbnailLoader.thumbnail(
                    for: url,
                    size: CGSize(width: 208, height: 128)
                )
                guard !Task.isCancelled else { return }
                thumbnailTasks[url] = nil
                guard let image else { return }
                thumbnailCache.setObject(image, forKey: url as NSURL)
                guard item?.representedURL == url else { return }
                item?.setThumbnail(image)
            }
        }

        private func fallbackImage(for url: URL, isAvailable: Bool) -> NSImage {
            guard isAvailable else {
                return NSImage(
                    systemSymbolName: "questionmark.folder",
                    accessibilityDescription: nil
                ) ?? NSImage()
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        private func selectedURLs() -> [URL] {
            guard let collectionView else { return [] }
            let indexes = IndexSet(collectionView.selectionIndexPaths.map(\.item))
            return indexes.sorted().compactMap {
                ResultShelfDragPayload.eligibleURL(at: $0, outputURLs: renderedURLs)
            }
        }

        private func copySelection() {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
        }

        private func revealSelection() {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            parent.onReveal(urls)
        }

    }
}

final class ResultShelfScrollView: NSScrollView {
    var onLayout: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureScrollerPresentation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScrollerPresentation()
    }

    override func layout() {
        super.layout()
        onLayout?(contentView.bounds.width)
    }

    private func configureScrollerPresentation() {
        scrollerStyle = .legacy
        autohidesScrollers = false
        let scroller = NSScroller()
        scroller.controlSize = .small
        horizontalScroller = scroller
    }
}

final class ResultShelfCollectionView: NSCollectionView {
    var copyTitle = "Copy"
    var revealTitle = "Show in Finder"
    var selectAllTitle = "Select All"
    var copyHandler: (() -> Void)?
    var revealHandler: (() -> Void)?
    var dragURLProvider: ((Int, IndexSet) -> [URL])?
    var draggingSessionStarter: (([NSDraggingItem], NSEvent) -> NSDraggingSession?)?

    private var pressedIndexPath: IndexPath?
    private var didStartDraggingForCurrentMouseDown = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressedIndexPath = indexPathForItem(at: point)
        didStartDraggingForCurrentMouseDown = false
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            revealHandler?()
        }
        pressedIndexPath = nil
        didStartDraggingForCurrentMouseDown = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDraggingForCurrentMouseDown,
            let clickedIndex = pressedIndexPath?.item
        else {
            super.mouseDragged(with: event)
            return
        }

        guard beginResultDrag(clickedIndex: clickedIndex, event: event) else {
            super.mouseDragged(with: event)
            return
        }
        didStartDraggingForCurrentMouseDown = true
    }

    @discardableResult
    func beginResultDrag(clickedIndex: Int, event: NSEvent) -> Bool {
        guard let dragURLProvider else { return false }
        let selectedIndexes = IndexSet(selectionIndexPaths.map(\.item))
        let urls = dragURLProvider(clickedIndex, selectedIndexes)
        guard !urls.isEmpty else { return false }

        let point = convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { offset, url in
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            let size = NSSize(width: 58, height: 58)
            let stagger = CGFloat(min(offset, 4)) * 3
            let frame = NSRect(
                x: point.x - size.width / 2 + stagger,
                y: point.y - size.height / 2 - stagger,
                width: size.width,
                height: size.height
            )
            draggingItem.setDraggingFrame(
                frame,
                contents: NSWorkspace.shared.icon(forFile: url.path)
            )
            return draggingItem
        }
        let session: NSDraggingSession?
        if let draggingSessionStarter {
            session = draggingSessionStarter(items, event)
        } else {
            session = beginDraggingSession(with: items, event: event, source: self)
        }
        session?.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    override func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let characters = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command), characters == "c" {
            copyHandler?()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            revealHandler?()
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point),
            !selectionIndexPaths.contains(indexPath)
        {
            selectionIndexPaths = [indexPath]
        }
        guard !selectionIndexPaths.isEmpty else { return nil }

        let menu = NSMenu()
        menu.addItem(withTitle: copyTitle, action: #selector(copySelectedResult), keyEquivalent: "")
        menu.addItem(withTitle: revealTitle, action: #selector(revealSelectedResult), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: selectAllTitle, action: #selector(selectAll(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func copySelectedResult() {
        copyHandler?()
    }

    @objc private func revealSelectedResult() {
        revealHandler?()
    }
}

final class ResultShelfCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ResultShelfCollectionItem")

    private let previewContainer = NSView()
    private let thumbnailView = NSImageView()
    private let filenameLabel = NSTextField(labelWithString: "")
    private let unavailableBadge = NSImageView()
    fileprivate var representedURL: URL?

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 9
        root.layer?.cornerCurve = .continuous

        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        previewContainer.layer?.cornerRadius = 8
        previewContainer.layer?.cornerCurve = .continuous
        previewContainer.layer?.masksToBounds = true

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.imageAlignment = .alignCenter
        filenameLabel.alignment = .center
        filenameLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        filenameLabel.textColor = .white.withAlphaComponent(0.78)
        filenameLabel.maximumNumberOfLines = 2
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.cell?.truncatesLastVisibleLine = true

        unavailableBadge.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        unavailableBadge.contentTintColor = .systemOrange
        unavailableBadge.isHidden = true

        [previewContainer, filenameLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }
        [thumbnailView, unavailableBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            previewContainer.addSubview($0)
        }

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 1),
            previewContainer.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            previewContainer.widthAnchor.constraint(equalToConstant: 104),
            previewContainer.heightAnchor.constraint(equalToConstant: 64),

            thumbnailView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 4),
            thumbnailView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -4),
            thumbnailView.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 3),
            thumbnailView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -3),

            unavailableBadge.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -5),
            unavailableBadge.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -5),
            unavailableBadge.widthAnchor.constraint(equalToConstant: 14),
            unavailableBadge.heightAnchor.constraint(equalToConstant: 14),

            filenameLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 2),
            filenameLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
            filenameLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 5),
            filenameLabel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor)
        ])

        view = root
        updateSelectionAppearance()
    }

    func configure(
        url: URL,
        image: NSImage,
        isAvailable: Bool,
        dragHelp: String,
        missingHelp: String
    ) {
        representedURL = url
        representedObject = url
        thumbnailView.image = image
        filenameLabel.stringValue = url.lastPathComponent
        filenameLabel.toolTip = url.lastPathComponent
        unavailableBadge.isHidden = isAvailable
        view.alphaValue = isAvailable ? 1 : 0.48
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(url.lastPathComponent)
        view.setAccessibilityHelp(isAvailable ? dragHelp : missingHelp)
    }

    func setThumbnail(_ image: NSImage) {
        thumbnailView.image = image
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        representedObject = nil
        thumbnailView.image = nil
        filenameLabel.stringValue = ""
        filenameLabel.toolTip = nil
        unavailableBadge.isHidden = true
        view.alphaValue = 1
    }

    private func updateSelectionAppearance() {
        view.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor
            : NSColor.clear.cgColor
        view.layer?.borderWidth = isSelected ? 1 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.82).cgColor
        filenameLabel.textColor = isSelected ? .white : .white.withAlphaComponent(0.78)
    }
}
