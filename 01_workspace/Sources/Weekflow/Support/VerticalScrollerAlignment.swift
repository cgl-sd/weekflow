import AppKit
import SwiftUI

/// Applies explicit AppKit geometry to the native scroll view created by
/// SwiftUI. The task card stack remains fully owned by SwiftUI; this bridge
/// removes system insets and aligns the scroller with the SwiftUI day-column
/// edge once the enclosing NSScrollView exists.
struct ZeroInsetVerticalScroller: NSViewRepresentable {
    let isVisible: Bool
    let columnWidth: CGFloat
    let scrollRequest: VerticalScrollRequest?
    let onTrackWidthChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollerProbeView()
        view.showsScroller = isVisible
        view.columnWidth = columnWidth
        view.scrollRequest = scrollRequest
        view.onTrackWidthChange = onTrackWidthChange
        view.configureEnclosingScrollView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ScrollerProbeView else { return }
        let scrollRequestChanged = view.scrollRequest?.id != scrollRequest?.id
        view.showsScroller = isVisible
        view.columnWidth = columnWidth
        view.scrollRequest = scrollRequest
        view.onTrackWidthChange = onTrackWidthChange
        view.configureEnclosingScrollView()
        if scrollRequestChanged {
            // Run after SwiftUI has committed the matching document extent,
            // but still inside AppKit's layout pass before the frame is drawn.
            view.needsLayout = true
        }
    }
}

struct VerticalScrollRequest: Equatable {
    let id: UUID
    let delta: CGFloat
}

private final class ScrollerProbeView: NSView {
    private var remainingConfigurationAttempts = 4
    private weak var configuredScrollView: NSScrollView?
    private weak var observedScroller: NSScroller?
    private weak var observedScrollView: NSScrollView?
    private var appliedScrollerVisibility: Bool?
    private var appliedBaseConfiguration = false
    private var isAligningScroller = false
    private var handledScrollRequestID: UUID?
    private var reportedTrackWidth: CGFloat?
    var showsScroller = false
    var columnWidth: CGFloat = 0
    var scrollRequest: VerticalScrollRequest?
    var onTrackWidthChange: ((CGFloat) -> Void)?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        remainingConfigurationAttempts = 4
        configureEnclosingScrollView()
    }

    override func layout() {
        super.layout()
        configureEnclosingScrollView(applyPendingScrollRequest: true)
    }

    func configureEnclosingScrollView(applyPendingScrollRequest: Bool = false) {
        guard let scrollView = enclosingScrollView else {
            guard superview != nil, remainingConfigurationAttempts > 0 else { return }
            remainingConfigurationAttempts -= 1
            DispatchQueue.main.async { [weak self] in
                self?.configureEnclosingScrollView(
                    applyPendingScrollRequest: applyPendingScrollRequest
                )
            }
            return
        }
        remainingConfigurationAttempts = 4
        if configuredScrollView !== scrollView {
            configuredScrollView = scrollView
            appliedBaseConfiguration = false
            appliedScrollerVisibility = nil
        }
        applyBaseConfigurationIfNeeded(to: scrollView)
        applyScrollerVisibilityIfNeeded(to: scrollView)
        if applyPendingScrollRequest {
            applyScrollRequestIfNeeded(to: scrollView)
        }
        guard showsScroller, let scroller = scrollView.verticalScroller else { return }
        observeFrameChanges(of: scroller, in: scrollView)
        alignScroller(scroller, in: scrollView)
    }

    private func applyBaseConfigurationIfNeeded(to scrollView: NSScrollView) {
        guard !appliedBaseConfiguration else { return }
        appliedBaseConfiguration = true
        scrollView.automaticallyAdjustsContentInsets = false
        let zeroInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentInsets = zeroInsets
        scrollView.scrollerInsets = zeroInsets
        scrollView.scrollerStyle = .legacy
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = false
    }

    private func applyScrollerVisibilityIfNeeded(to scrollView: NSScrollView) {
        guard appliedScrollerVisibility != showsScroller else { return }
        appliedScrollerVisibility = showsScroller
        scrollView.autohidesScrollers = !showsScroller
        scrollView.hasVerticalScroller = showsScroller
        scrollView.verticalScroller?.isHidden = !showsScroller
        // Creating or removing the legacy scroller requires one AppKit tile.
        // Repeating it on every SwiftUI animation frame forces the knob to
        // recalculate from transient document heights and causes visible jumps.
        scrollView.tile()
    }

    private func applyScrollRequestIfNeeded(to scrollView: NSScrollView) {
        guard let scrollRequest,
              handledScrollRequestID != scrollRequest.id else { return }
        performScrollRequest(scrollRequest, in: scrollView)
    }

    private func performScrollRequest(_ scrollRequest: VerticalScrollRequest, in scrollView: NSScrollView) {
        guard self.scrollRequest?.id == scrollRequest.id,
              handledScrollRequestID != scrollRequest.id,
              let documentView = scrollView.documentView else { return }
        // Mark the request before forcing layout so a nested AppKit layout
        // callback cannot apply the same movement a second time.
        handledScrollRequestID = scrollRequest.id
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let maximumY = max(documentView.bounds.height - clipView.bounds.height, 0)
        let targetY = min(
            max(clipView.bounds.origin.y + scrollRequest.delta, 0),
            maximumY
        )
        guard abs(targetY - clipView.bounds.origin.y) >= 0.5 else { return }

        // The menu reserve already establishes the final document extent.
        // Settling the clip origin in this same display cycle prevents the
        // legacy scroller from rendering an old position for one frame and
        // then making a large ease-out jump on the next frame.
        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func observeFrameChanges(of scroller: NSScroller, in scrollView: NSScrollView) {
        guard observedScroller !== scroller || observedScrollView !== scrollView else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSView.frameDidChangeNotification,
            object: observedScroller
        )
        observedScroller = scroller
        observedScrollView = scrollView
        scroller.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollerFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scroller
        )
    }

    @objc private func scrollerFrameDidChange(_ notification: Notification) {
        guard
            let scroller = notification.object as? NSScroller,
            scroller === observedScroller,
            let scrollView = observedScrollView
        else { return }
        alignScroller(scroller, in: scrollView)
    }

    private func alignScroller(_ scroller: NSScroller, in scrollView: NSScrollView) {
        guard !isAligningScroller else { return }
        // SwiftUI's internal NSScrollView is narrower than the outer day-column
        // frame once the legacy scroller is installed. Use the SwiftUI-owned
        // column width so the native scroller ends at the real column edge.
        let targetMaxX = scrollView.bounds.minX + columnWidth
        let targetWidth = scroller.frame.width
        let targetFrame = NSRect(
            x: targetMaxX - targetWidth,
            y: scroller.frame.minY,
            width: targetWidth,
            height: scroller.frame.height
        )
        if abs(scroller.frame.minX - targetFrame.minX) >= 0.5
            || abs(scroller.frame.width - targetFrame.width) >= 0.5 {
            isAligningScroller = true
            scroller.frame = targetFrame
            isAligningScroller = false
        }
        reportTrackWidthIfNeeded(targetWidth)
    }

    private func reportTrackWidthIfNeeded(_ width: CGFloat) {
        guard width > 0,
              reportedTrackWidth.map({ abs($0 - width) >= 0.5 }) ?? true else { return }
        reportedTrackWidth = width
        DispatchQueue.main.async { [weak self] in
            self?.onTrackWidthChange?(width)
        }
    }
}
