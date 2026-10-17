import SwiftUI
import UIKit

// MARK: - BackportHostingConfiguration (iOS 16 backport)
//
// Backport of SwiftUI's `BackportHostingConfiguration` (iOS 16+) built on the
// `UIContentConfiguration` / `UIContentView` protocols, which exist since
// iOS 14. Covers the surface this app uses: the content/background builders,
// `.margins(_:_)` and `.minSize(width:height:)`.

public struct BackportHostingConfiguration<Content: View, Background: View>: UIContentConfiguration {
    var content: Content
    var background: Background
    var margins: UIEdgeInsets
    var minSize: CGSize?

    public init(@ViewBuilder content: () -> Content) where Background == EmptyView {
        self.content = content()
        self.background = EmptyView()
        // Real BackportHostingConfiguration defaults: 11pt vertical, 16pt horizontal.
        self.margins = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        self.minSize = nil
    }

    public init(@ViewBuilder content: () -> Content, @ViewBuilder background: () -> Background) {
        self.content = content()
        self.background = background()
        // Real BackportHostingConfiguration defaults: 11pt vertical, 16pt horizontal.
        self.margins = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        self.minSize = nil
    }

    /// Backport of `.margins(_:_:)`.
    public func margins(_ edges: Edge.Set = .all, _ length: CGFloat) -> BackportHostingConfiguration<Content, Background> {
        var copy = self
        var m = copy.margins
        if edges.contains(.top) || edges == .all { m.top = length }
        if edges.contains(.bottom) || edges == .all { m.bottom = length }
        if edges.contains(.leading) || edges == .all { m.left = length }
        if edges.contains(.trailing) || edges == .all { m.right = length }
        copy.margins = m
        return copy
    }

    /// Backport of `.minSize(width:height:)` (iOS 17+).
    public func minSize(width: CGFloat? = nil, height: CGFloat? = nil) -> BackportHostingConfiguration<Content, Background> {
        var copy = self
        copy.minSize = CGSize(width: width ?? 0, height: height ?? 0)
        return copy
    }

    /// Backport of `.background(_:)` with a ViewBuilder background.
    public func background<B: View>(@ViewBuilder _ background: () -> B) -> BackportHostingConfiguration<Content, B> {
        BackportHostingConfiguration<Content, B>(
            content: { self.content },
            background: background
        )
    }

    public func makeContentView() -> UIView {
        BackportHostingContentView(content: content, background: background, margins: margins, minSize: minSize)
    }

    public func updated(for state: UIConfigurationState) -> BackportHostingConfiguration<Content, Background> {
        self
    }

    /// `UIContentConfiguration` refines `NSCopying`, so the conformance needs
    /// this even though the type is a value type.
    public func copy(with zone: NSZone? = nil) -> Any {
        self
    }
}

// MARK: - Content view

/// The UIView returned by `makeContentView()`. Conforms to `UIContentView` so
/// UICollectionView/UITableView reuse updates the existing hosting controller
/// instead of rebuilding the SwiftUI hierarchy on every reconfigure.
final class BackportHostingContentView<Content: View, Background: View>: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet { applyConfiguration() }
    }

    private var current: BackportHostingConfiguration<Content, Background>?
    private var contentController: UIHostingController<Content>?
    private var backgroundController: UIHostingController<Background>?
    private var constraintsInstalled = false
    private var contentMargins: UIEdgeInsets = .zero
    private var minimumSize: CGSize?

    init(content: Content, background: Background, margins: UIEdgeInsets, minSize: CGSize?) {
        self.configuration = BackportHostingConfiguration(content: { content }, background: { background })
        self.current = BackportHostingConfiguration(content: { content }, background: { background })
        self.contentMargins = margins
        self.minimumSize = minSize
        super.init(frame: .zero)
        backgroundColor = .clear
        applyConfiguration()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func applyConfiguration() {
        guard let config = configuration as? BackportHostingConfiguration<Content, Background> else { return }
        contentMargins = config.margins
        minimumSize = config.minSize

        if let controller = contentController {
            controller.rootView = config.content
        } else {
            let controller = UIHostingController(rootView: config.content)
            controller.view.backgroundColor = .clear
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(controller.view)
            contentController = controller
        }

        if let controller = backgroundController {
            controller.rootView = config.background
        } else {
            let controller = UIHostingController(rootView: config.background)
            controller.view.backgroundColor = .clear
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            insertSubview(controller.view, at: 0)
            backgroundController = controller
        }

        current = config
        installConstraints()
    }

    private func installConstraints() {
        if !constraintsInstalled {
            constraintsInstalled = true
        }
        // Remove previous layout margins constraints and rebuild (margins can
        // change between configurations).
        for constraint in constraints where constraint.identifier?.hasPrefix("bphc") == true {
            constraint.isActive = false
        }
        guard let contentView = contentController?.view, let backgroundView = backgroundController?.view else { return }

        let m = contentMargins
        var all: [NSLayoutConstraint] = [
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: m.top),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -m.bottom),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -m.right),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ]
        if let minSize = minimumSize, minSize != .zero {
            if minSize.width > 0 {
                all.append(contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: minSize.width))
            }
            if minSize.height > 0 {
                all.append(contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: minSize.height))
            }
        }
        for (index, constraint) in all.enumerated() {
            constraint.identifier = "bphc-\(index)"
            constraint.isActive = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Sizing is driven by the Auto Layout constraints against the hosting
        // controller's view; nothing extra to do here.
    }
}
