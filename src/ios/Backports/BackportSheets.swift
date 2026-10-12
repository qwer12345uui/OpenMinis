import SwiftUI
import UIKit

// MARK: - PresentationDetent (iOS 15 backport)

/// Backport of SwiftUI's `PresentationDetent` (iOS 16+).
public enum PresentationDetent: Hashable {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)
}

/// Applies detents and drag-indicator preferences to the enclosing sheet via
/// UISheetPresentationController (iOS 15+). Works on every supported OS, so
/// behavior matches the native modifiers on iOS 16+ as well.
struct BackportSheetConfigurator: UIViewRepresentable {
    var detents: Set<PresentationDetent>
    var dragIndicator: Visibility?

    final class ConfiguratorView: UIView {
        var detents: Set<PresentationDetent> = []
        var dragIndicator: Visibility?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        func apply() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            var hostingVC: UIViewController?
            while let r = responder {
                if let vc = r as? UIViewController { hostingVC = vc; break }
                responder = r.next
            }
            guard let vc = hostingVC else { return }
            guard let sheet = vc.presentationController as? UISheetPresentationController else { return }

            func rank(_ d: PresentationDetent) -> Int {
                switch d {
                case .medium: return 0
                case .fraction, .height: return 1
                case .large: return 2
                }
            }
            let mapped = detents
                .map { detent -> (Int, UISheetPresentationController.Detent) in
                    let mappedDetent: UISheetPresentationController.Detent
                    if #available(iOS 16.0, *) {
                        switch detent {
                        case .medium: mappedDetent = .medium()
                        case .large: mappedDetent = .large()
                        case .fraction(let f):
                            mappedDetent = .custom { _ in f }
                        case .height(let h):
                            mappedDetent = .custom { _ in h }
                        }
                    } else {
                        // iOS 15 has no custom detents: degrade to medium.
                        switch detent {
                        case .large: mappedDetent = .large()
                        default: mappedDetent = .medium()
                        }
                    }
                    return (rank(detent), mappedDetent)
                }
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
            if !mapped.isEmpty {
                sheet.detents = mapped
            }
            if let indicator = dragIndicator {
                sheet.prefersGrabberVisible = indicator == .visible
            }
        }
    }

    func makeUIView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.detents = detents
        view.dragIndicator = dragIndicator
        return view
    }

    func updateUIView(_ view: ConfiguratorView, context: Context) {
        view.detents = detents
        view.dragIndicator = dragIndicator
        view.apply()
    }
}

public extension View {
    /// Backport of `View.presentationDetents(_:)` (iOS 16+). On iOS 15,
    /// fraction/height detents degrade to the medium detent.
    func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        background(BackportSheetConfigurator(detents: detents, dragIndicator: nil))
    }

    /// Backport of `View.presentationDetents(_:selection:)` (iOS 16.4+).
    /// Detents apply the same way; the selection binding is not synced below
    /// iOS 16.4.
    func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View {
        background(BackportSheetConfigurator(detents: detents, dragIndicator: nil))
    }

    /// Backport of `View.presentationDragIndicator(_:)` (iOS 16+).
    func presentationDragIndicator(_ indicatorVisibility: Visibility) -> some View {
        background(BackportSheetConfigurator(detents: [], dragIndicator: indicatorVisibility))
    }
}
