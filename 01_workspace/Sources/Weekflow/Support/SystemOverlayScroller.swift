import AppKit
import SwiftUI

/// Keeps settings-style scroll views on the native macOS overlay scroller:
/// no reserved track, hidden while idle, and briefly visible while scrolling.
struct SystemOverlayScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = SystemOverlayScrollerProbe()
        view.configureEnclosingScrollView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SystemOverlayScrollerProbe)?.configureEnclosingScrollView()
    }
}

private final class SystemOverlayScrollerProbe: NSView {
    private weak var configuredScrollView: NSScrollView?
    private var hideWorkItem: DispatchWorkItem?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    override func layout() {
        super.layout()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        guard let scrollView = nearestScrollView else { return }
        if configuredScrollView !== scrollView {
            NotificationCenter.default.removeObserver(self)
            configuredScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            hideScroller(in: scrollView)
        }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.verticalScroller?.controlSize = .regular
        scrollView.tile()
    }

    @objc private func contentBoundsDidChange(_ notification: Notification) {
        guard let scrollView = configuredScrollView else { return }
        showScrollerTemporarily(in: scrollView)
    }

    private func showScrollerTemporarily(in scrollView: NSScrollView) {
        guard let scroller = scrollView.verticalScroller else { return }
        hideWorkItem?.cancel()
        scroller.isHidden = false
        scroller.alphaValue = 1

        let workItem = DispatchWorkItem { [weak self, weak scrollView] in
            guard let self, let scrollView else { return }
            self.hideScroller(in: scrollView)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func hideScroller(in scrollView: NSScrollView) {
        guard let scroller = scrollView.verticalScroller else { return }
        scroller.alphaValue = 0
        scroller.isHidden = true
    }

    private var nearestScrollView: NSScrollView? {
        sequence(first: superview, next: { $0?.superview })
            .compactMap { $0 as? NSScrollView }
            .first
    }
}
