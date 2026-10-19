import SwiftUI
import UIKit
import QuickLook

// MARK: - AnyShape (iOS 16 backport)

/// Backport of SwiftUI's `AnyShape` (iOS 16+).
public struct AnyShape: Shape {
    private let pathMaker: (CGRect) -> Path

    public init<S: Shape>(_ shape: S) {
        pathMaker = { rect in shape.path(in: rect) }
    }

    public func path(in rect: CGRect) -> Path {
        pathMaker(rect)
    }
}

// MARK: - UnevenRoundedRectangle (iOS 16.4 backport)

/// Backport of SwiftUI's `UnevenRoundedRectangle` (iOS 16.4+) with
/// per-corner radii. Continuous-corner style is approximated with circular
/// arcs (visually near-identical at the radii this app uses).
public struct UnevenRoundedRectangle: Shape {
    public var topLeadingRadius: CGFloat
    public var bottomLeadingRadius: CGFloat
    public var bottomTrailingRadius: CGFloat
    public var topTrailingRadius: CGFloat
    public var style: RoundedCornerStyle

    public init(topLeadingRadius: CGFloat = 0,
                bottomLeadingRadius: CGFloat = 0,
                bottomTrailingRadius: CGFloat = 0,
                topTrailingRadius: CGFloat = 0,
                style: RoundedCornerStyle = .continuous) {
        self.topLeadingRadius = topLeadingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topTrailingRadius = topTrailingRadius
        self.style = style
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = min(topLeadingRadius, min(rect.width, rect.height) / 2)
        let bl = min(bottomLeadingRadius, min(rect.width, rect.height) / 2)
        let br = min(bottomTrailingRadius, min(rect.width, rect.height) / 2)
        let tr = min(topTrailingRadius, min(rect.width, rect.height) / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        // Top edge → top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                        radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        // Right edge → bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                        radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        // Bottom edge → bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                        radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        // Left edge → top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                        radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - LabeledContent (iOS 16 backport)

/// Backport of SwiftUI's `LabeledContent` (iOS 16+). Forwards to the real
/// implementation on iOS 16+; falls back to an equivalent HStack layout below.
public struct LabeledContent<Label: View, Value: View>: View {
    private let label: Label
    private let value: Value

    /// General form: `LabeledContent { value } label: { label }`.
    public init(@ViewBuilder content: () -> Value, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.value = content()
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            SwiftUI.LabeledContent(content: { value }, label: { label })
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                label
                Spacer(minLength: 8)
                value.foregroundStyle(.secondary)
            }
        }
    }
}

public extension LabeledContent where Label == Text, Value == Text {
    init(_ titleKey: LocalizedStringKey, value: some StringProtocol) {
        self.label = Text(titleKey)
        self.value = Text(String(value))
    }

    init(_ title: some StringProtocol, value: some StringProtocol) {
        self.label = Text(String(title))
        self.value = Text(String(value))
    }
}

public extension LabeledContent where Label == Text {
    init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Value) {
        self.label = Text(titleKey)
        self.value = content()
    }

    init(_ title: some StringProtocol, @ViewBuilder content: () -> Value) {
        self.label = Text(String(title))
        self.value = content()
    }
}

// MARK: - ShareLink (iOS 16 backport)

/// Backport of the `ShareLink(item:)` forms used by the app. Forwards to the
/// real ShareLink on iOS 16+; presents a UIActivityViewController on iOS 15.
public struct ShareLink: View {
    private enum Payload {
        case url(URL)
        case string(String)
    }

    private let payload: Payload

    public init(item: URL) {
        payload = .url(item)
    }

    public init(item: String) {
        payload = .string(item)
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            switch payload {
            case .url(let url): SwiftUI.ShareLink(item: url)
            case .string(let string): SwiftUI.ShareLink(item: string)
            }
        } else {
            Button {
                BackportSharePresenter.present(urlOrString)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private var urlOrString: Any {
        switch payload {
        case .url(let url): return url
        case .string(let string): return string
        }
    }
}

enum BackportSharePresenter {
    @MainActor
    static func present(_ item: Any) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        else { return }
        var top: UIViewController = window.rootViewController ?? UIViewController()
        while let presented = top.presentedViewController { top = presented }
        let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        // iPad: anchor to the middle of the screen.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(activity, animated: true)
    }
}

// MARK: - Small no-op / legacy shims

/// Backport of SwiftUI's `ScrollIndicatorVisibility` (iOS 16+).
public struct ScrollIndicatorVisibility: Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let automatic = ScrollIndicatorVisibility(rawValue: 0)
    public static let visible = ScrollIndicatorVisibility(rawValue: 1)
    public static let hidden = ScrollIndicatorVisibility(rawValue: 2)
}

public extension View {
    /// Backport of `View.scrollIndicators(_:)` (iOS 16+). Indicators already
    /// show during scrolling on iOS 15, so this is a no-op there.
    func scrollIndicators(_ visibility: ScrollIndicatorVisibility) -> some View {
        self
    }

    /// Backport of `View.scrollContentBackground(_:)` (iOS 16+). No-op on
    /// iOS 15 — List keeps its default background there.
    func scrollContentBackground(_ visibility: Visibility) -> some View {
        self
    }

    /// Backport of `View.persistentSystemOverlays(_:)` (iOS 16+). No-op on
    /// iOS 15 (no persistent overlays exist there).
    func persistentSystemOverlays(_ visibility: Visibility) -> some View {
        self
    }

    /// Backport of `View.statusBarHidden(_:)` (iOS 16); maps to the legacy
    /// `statusBar(hidden:)` modifier.
    func statusBarHidden(_ hidden: Bool = true) -> some View {
        self.statusBar(hidden: hidden)
    }

    /// Backport of `View.toolbarBackground(_:for:)` (ShapeStyle, iOS 16+).
    /// Cosmetic only; no-op on iOS 15.
    func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacement...) -> some View {
        self
    }

    /// Backport of `View.toolbarBackground(_:for:)` (Visibility, iOS 16+).
    /// Cosmetic only; no-op on iOS 15.
    func toolbarBackground(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        self
    }

    /// Backport of `View.toolbarBackgroundVisibility(_:for:)` (iOS 18+).
    /// Cosmetic only; no-op below iOS 18.
    func toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        self
    }

    /// Backport of `View.toolbar(_:for:)` (iOS 16+). Drives the underlying
    /// UINavigationController bar visibility, which works on iOS 15 too.
    func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        background(BackportNavBarVisibility(visibility: visibility))
    }

    /// Backport of `View.scrollDismissesKeyboard(_:)` (iOS 16+). Maps to the
    /// enclosing UIScrollView's keyboardDismissMode on iOS 15.
    func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View {
        background(BackportScrollKeyboardDismiss(mode: mode))
    }

    /// Backport of `View.navigationSplitViewColumnWidth(min:ideal:max:)`
    /// (iOS 16+). No-op on iOS 15 (default column widths are used).
    func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> some View {
        self
    }
}

// MARK: - ToolbarPlacement (iOS 16 backport)

/// Backport of SwiftUI's `ToolbarPlacement` (iOS 16+).
public struct ToolbarPlacement: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let navigationBar = ToolbarPlacement(rawValue: 1 << 0)
    public static let tabBar = ToolbarPlacement(rawValue: 1 << 1)
    public static let bottomBar = ToolbarPlacement(rawValue: 1 << 2)
    public static let statusBar = ToolbarPlacement(rawValue: 1 << 3)
}

struct BackportNavBarVisibility: UIViewRepresentable {
    var visibility: Visibility

    final class VisibilityView: UIView {
        var visibility: Visibility = .automatic

        override func didMoveToWindow() {
            super.didMoveToWindow()
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
            guard let nav = hostingVC?.navigationController else { return }
            let hidden = visibility == .hidden
            if nav.isNavigationBarHidden != hidden {
                nav.setNavigationBarHidden(hidden, animated: false)
            }
        }
    }

    func makeUIView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.visibility = visibility
        return view
    }

    func updateUIView(_ view: VisibilityView, context: Context) {
        view.visibility = visibility
        view.apply()
    }
}

// MARK: - ScrollDismissesKeyboardMode (iOS 16 backport)

/// Backport of SwiftUI's `ScrollDismissesKeyboardMode` (iOS 16+).
public struct ScrollDismissesKeyboardMode: Hashable {
    public let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    public static let automatic = ScrollDismissesKeyboardMode(rawValue: 0)
    public static let immediately = ScrollDismissesKeyboardMode(rawValue: 1)
    public static let interactively = ScrollDismissesKeyboardMode(rawValue: 2)
    public static let never = ScrollDismissesKeyboardMode(rawValue: 3)
}

struct BackportScrollKeyboardDismiss: UIViewRepresentable {
    var mode: ScrollDismissesKeyboardMode

    final class DismissView: UIView {
        var mode: ScrollDismissesKeyboardMode = .automatic

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard window != nil else { return }
            var ancestor: UIView? = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    switch mode {
                    case .never: scrollView.keyboardDismissMode = .none
                    case .immediately: scrollView.keyboardDismissMode = .onDrag
                    case .interactively: scrollView.keyboardDismissMode = .interactive
                    default: scrollView.keyboardDismissMode = .onDrag
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }

    func makeUIView(context: Context) -> DismissView {
        let view = DismissView()
        view.mode = mode
        return view
    }

    func updateUIView(_ view: DismissView, context: Context) {
        view.mode = mode
        view.apply()
    }
}

// MARK: - GrowingTextField

/// Replacement for `TextField(_:text:axis: .vertical)` (iOS 16+). On iOS 15
/// the field falls back to the native single-line TextField.
public struct GrowingTextField: View {
    private enum Title {
        case key(LocalizedStringKey)
        case raw(String)
    }

    private let title: Title
    private let text: Binding<String>

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.title = .key(titleKey)
        self.text = text
    }

    public init(_ title: some StringProtocol, text: Binding<String>) {
        self.title = .raw(String(title))
        self.text = text
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            TextField(titleKey, text: text, axis: .vertical)
        } else {
            TextField(titleKey, text: text)
        }
    }

    private var titleKey: LocalizedStringKey {
        switch title {
        case .key(let key): return key
        case .raw(let raw): return LocalizedStringKey(raw)
        }
    }

    /// Backport of `View.lineLimit(_ limit: ClosedRange<Int>)` (iOS 16+),
    /// commonly chained onto vertical TextFields. On iOS 15 the upper bound is
    /// used as the fixed limit.
    public func lineLimit(_ range: ClosedRange<Int>) -> some View {
        if #available(iOS 16.0, *) {
            return AnyView(body.lineLimit(range))
        } else {
            return AnyView(body.lineLimit(range.upperBound))
        }
    }
}

// MARK: - NavigationSplitView (iOS 16 backport)

/// Backport of SwiftUI's `NavigationSplitViewVisibility` (iOS 16+).
public enum NavigationSplitViewVisibility: Equatable {
    case automatic
    case all
    case doubleColumn
    case detailOnly
    case secondaryOnly
}

/// Backport of SwiftUI's `NavigationSplitView` (iOS 16+). Forwards to the real
/// implementation on iOS 16+; falls back to a two-column NavigationView below.
public struct NavigationSplitView<Sidebar: View, Detail: View>: View {
    private let columnVisibility: Binding<NavigationSplitViewVisibility>?
    private let sidebar: Sidebar
    private let detail: Detail

    public init(columnVisibility: Binding<NavigationSplitViewVisibility>? = nil,
                @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder detail: () -> Detail) {
        self.columnVisibility = columnVisibility
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            SwiftUI.NavigationSplitView(
                columnVisibility: mappedVisibility ?? Binding.constant(SwiftUI.NavigationSplitViewVisibility.automatic),
                sidebar: { sidebar },
                detail: { detail }
            )
        } else {
            NavigationView {
                sidebar
                detail
            }
        }
    }

    @available(iOS 16.0, *)
    private var mappedVisibility: Binding<SwiftUI.NavigationSplitViewVisibility>? {
        guard let columnVisibility else { return nil }
        return Binding(
            get: { Self.map(columnVisibility.wrappedValue) },
            set: { columnVisibility.wrappedValue = Self.unmap($0) }
        )
    }

    @available(iOS 16.0, *)
    private static func map(_ value: NavigationSplitViewVisibility) -> SwiftUI.NavigationSplitViewVisibility {
        switch value {
        case .automatic: return .automatic
        case .all: return .all
        case .doubleColumn: return .doubleColumn
        case .detailOnly: return .detailOnly
        case .secondaryOnly: return .automatic
        }
    }

    @available(iOS 16.0, *)
    private static func unmap(_ value: SwiftUI.NavigationSplitViewVisibility) -> NavigationSplitViewVisibility {
        switch value {
        case .all: return .all
        case .doubleColumn: return .doubleColumn
        case .detailOnly: return .detailOnly
        default: return .automatic
        }
    }
}

// MARK: - Locale (iOS 15 fallbacks)

public extension Locale {
    /// iOS 15 fallback for `Locale.language.languageCode?.identifier` (iOS 16+).
    /// `Locale.languageCode` carries the same value and has been available since
    /// iOS 10; it is only *deprecated* on iOS 16+, never removed.
    var backportLanguageCode: String? {
        if #available(iOS 16.0, *) {
            return language.languageCode?.identifier
        }
        return languageCode
    }

    /// iOS 15 fallback for `Locale.region?.identifier` (iOS 16+).
    var backportRegionCode: String? {
        if #available(iOS 16.0, *) {
            return region?.identifier
        }
        return regionCode
    }
}

// MARK: - quickLookPreview (iOS 16 backport)
//
// SwiftUI's `.quickLookPreview(_:)` is iOS 16.0+. Referencing it from code
// that also runs on iOS 15 build-links `_QuickLook_SwiftUI.framework` into
// the app; dyld then refuses to launch the whole process on iOS 15 with
// "Library not loaded: /System/Library/Frameworks/_QuickLook_SwiftUI.framework".
// Wrapping the call in an availability check keeps the reference weak, and
// iOS 15 gets an equivalent QLPreviewController presented in a sheet.

public extension View {
    /// iOS 15-safe replacement for `View.quickLookPreview(_:)`.
    @ViewBuilder
    func minisQuickLookPreview(_ url: Binding<URL?>) -> some View {
        if #available(iOS 16.0, *) {
            self.quickLookPreview(url)
        } else {
            self.sheet(item: Binding(
                get: { url.wrappedValue.map(MinisQuickLookItem.init) },
                set: { url.wrappedValue = $0?.url }
            )) { item in
                MinisQuickLookContainer(url: item.url)
            }
        }
    }
}

public struct MinisQuickLookItem: Identifiable {
    public let url: URL
    public var id: String { url.absoluteString }
    public init(_ url: URL) { self.url = url }
}

private struct MinisQuickLookContainer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
