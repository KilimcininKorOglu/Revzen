import AppKit
import Observation
import RevzenCore
import SwiftUI

/// What the preview panel shows.
@MainActor
@Observable
final class PreviewModel {
    var windows: [PreviewWindow] = []
    var images: [CGWindowID: CGImage] = [:]
    var appIcon = NSImage()
    var layout = PreviewLayout(count: 1, edge: .bottom, available: .greatestFiniteMagnitude)
    var edge = DockEdge.bottom

    @ObservationIgnored var onSelect: (PreviewWindow) -> Void = { _ in }
    @ObservationIgnored var onClose: (PreviewWindow) -> Void = { _ in }

    func image(for window: PreviewWindow) -> CGImage? {
        window.windowID.flatMap { images[$0] }
    }
}

/// A borderless panel that floats above the Dock and never takes focus, so
/// the app under the pointer keeps its active state.
@MainActor
final class PreviewPanel: NSPanel {
    static let cornerRadius: CGFloat = 12

    init(model: PreviewModel) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        // The popover material follows the system light and dark appearance.
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.masksToBounds = true

        let host = NSHostingView(rootView: PreviewGrid(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Window tiles in a row for a bottom Dock, in a column for a side Dock.
struct PreviewGrid: View {
    let model: PreviewModel

    var body: some View {
        let stack = model.edge.isVertical
            ? AnyLayout(VStackLayout(spacing: PreviewLayout.spacing))
            : AnyLayout(HStackLayout(spacing: PreviewLayout.spacing))
        stack {
            ForEach(model.windows) { window in
                PreviewTile(
                    window: window,
                    image: model.image(for: window),
                    appIcon: model.appIcon,
                    imageSize: model.layout.imageSize,
                    onSelect: { model.onSelect(window) },
                    onClose: { model.onClose(window) }
                )
            }
        }
        .padding(PreviewLayout.padding)
        .frame(width: model.layout.panelSize.width, height: model.layout.panelSize.height)
    }
}

private struct PreviewTile: View {
    let window: PreviewWindow
    let image: CGImage?
    let appIcon: NSImage
    let imageSize: CGSize
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
                .frame(width: imageSize.width, height: imageSize.height)
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        CloseButton(action: onClose)
                    }
                }
            Text(window.title.isEmpty ? " " : window.title)
                .font(.caption)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: imageSize.width, height: PreviewLayout.titleHeight - 4)
        }
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
                .padding(-4)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .overlay { MiddleClickCatcher(action: onClose) }
        .help(window.title)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .opacity(window.window.isMinimized ? 0.6 : 1)
        } else {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: min(64, imageSize.height * 0.6))
                .opacity(0.8)
        }
    }
}

/// The "x" in the corner of a hovered tile.
private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.primary, .regularMaterial)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
        .help("Close Window")
        .padding(4)
    }
}

/// Catches middle clicks on a tile. SwiftUI has no gesture for the middle
/// button, so an AppKit view takes the hit test for that button only and
/// lets every other event reach the SwiftUI views below it.
private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .otherMouseDown ? super.hitTest(point) : nil
        }

        override func otherMouseDown(with event: NSEvent) {
            // Button 2 is the middle button. Other extra buttons are ignored.
            guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
            action()
        }
    }
}
