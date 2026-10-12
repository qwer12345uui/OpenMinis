import SwiftUI
import UIKit

// MARK: - NavigationPath (iOS 15 backport)
//
// Backport of SwiftUI's `NavigationPath` (iOS 16+). Only the public surface the
// app relies on is modeled: append, removeLast, count, isEmpty, and
// value-semantics equality for `.onChange(of:)`. Like the real type, elements
// are opaque (no public accessors).

public struct NavigationPath: Equatable {
    var elements: [AnyHashable] = []

    public init() {}

    public init<S: Hashable>(_ elements: [S]) {
        self.elements = elements.map { AnyHashable($0) }
    }

    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public static func == (lhs: NavigationPath, rhs: NavigationPath) -> Bool {
        lhs.elements == rhs.elements
    }
}

// MARK: - Destination registry

/// Type-erased destination factory registered by `.navigationDestination(for:)`.
@MainActor
final class BackportDestinationBox {
    private let make: (AnyHashable) -> AnyView

    init<D: Hashable, V: View>(_ type: D.Type, _ factory: @escaping (D) -> V) {
        self.make = { value in
            guard let typed = value.base as? D else { return AnyView(EmptyView()) }
            return AnyView(factory(typed))
        }
    }

    func destination(for value: AnyHashable) -> AnyView {
        make(value)
    }
}

/// Preference payload carrying destination factories up to the enclosing
/// backport `NavigationStack`.
struct BackportDestinations: Equatable {
    var boxes: [ObjectIdentifier: BackportDestinationBox] = [:]

    static func == (lhs: BackportDestinations, rhs: BackportDestinations) -> Bool {
        lhs.boxes.keys.sorted { $0.hashValue < $1.hashValue }
            == rhs.boxes.keys.sorted { $0.hashValue < $1.hashValue }
    }
}

struct BackportDestinationsKey: PreferenceKey {
    static var defaultValue: BackportDestinations = .init()

    static func reduce(value: inout BackportDestinations, nextValue: () -> BackportDestinations) {
        value.boxes.merge(nextValue().boxes) { _, new in new }
    }
}

public extension View {
    /// Backport of `View.navigationDestination(for:destination:)` (iOS 16+).
    /// Registers a typed destination factory with the enclosing backport
    /// `NavigationStack`; works on iOS 15 and newer.
    func navigationDestination<D: Hashable, V: View>(for type: D.Type,
                                                     @ViewBuilder destination: @escaping (D) -> V) -> some View {
        let box = BackportDestinationBox(D.self, destination)
        return preference(
            key: BackportDestinationsKey.self,
            value: BackportDestinations(boxes: [ObjectIdentifier(D.self): box])
        )
    }
}

// MARK: - Router environment

@MainActor
final class BackportNavRouter: ObservableObject {
    /// Actual depth of the underlying UINavigationController (ground truth,
    /// reconciled by the delegate proxy). Drives the hidden link chain.
    @Published var depth: Int = 0

    /// Number of native (non value-based) pushes sitting below the path-managed
    /// portion of the stack.
    var nativeExtra: Int = 0

    var pathBinding: Binding<NavigationPath>?
    var ownedPath = NavigationPath()
    private var pathSnapshot = NavigationPath()

    /// Registered destination factories (collected via preference).
    var destinations: BackportDestinations = .init() {
        didSet { retainDestinations() }
    }
    private func retainDestinations() {
        // Preference boxes are classes; nothing to do beyond keeping the dict.
    }

    var path: NavigationPath { pathBinding?.wrappedValue ?? ownedPath }

    func configure(pathBinding: Binding<NavigationPath>?) {
        self.pathBinding = pathBinding
    }

    /// Called when the externally-owned path binding changes (programmatic
    /// navigation such as share-extension pushes).
    func pathChangedExternally(_ newPath: NavigationPath) {
        guard newPath != pathSnapshot else { return }
        pathSnapshot = newPath
        depth = nativeExtra + newPath.count
    }

    /// Initial sync when the stack first attaches.
    func syncInitial() {
        let p = path
        pathSnapshot = p
        depth = nativeExtra + p.count
    }

    /// Value-based push from the backport `NavigationLink(value:)`.
    func push<V: Hashable>(_ value: V) {
        var p = path
        p.append(value)
        writePath(p)
        depth = nativeExtra + p.count
    }

    private func writePath(_ p: NavigationPath) {
        pathSnapshot = p
        if let binding = pathBinding {
            binding.wrappedValue = p
        } else {
            ownedPath = p
        }
    }

    /// Reconcile with the actual UINavigationController depth (delegate proxy).
    func reconcile(actualDepth: Int) {
        guard actualDepth != depth else { return }
        if actualDepth > depth {
            // Native push(es): they sit on top of the path-managed portion.
            nativeExtra += actualDepth - depth
            depth = actualDepth
            return
        }
        // Pop(s): trim native extras first, then the path-managed tail.
        let removed = depth - actualDepth
        depth = actualDepth
        var newExtra = max(0, nativeExtra - removed)
        let pathRemove = max(0, removed - nativeExtra)
        nativeExtra = newExtra
        if pathRemove > 0 {
            var p = path
            let drop = min(pathRemove, p.elements.count)
            if drop > 0 {
                p.elements.removeLast(drop)
                writePath(p)
            }
        }
    }

    /// Destination view for a given *path* index (0-based into elements).
    @ViewBuilder
    func destinationView(pathIndex: Int) -> some View {
        let p = path
        if p.elements.indices.contains(pathIndex) {
            let element = p.elements[pathIndex]
            if let box = destinations.boxes[ObjectIdentifier(type(of: element.base))] {
                box.destination(for: element)
            } else {
                Color.clear
            }
        } else {
            Color.clear
        }
    }

    /// Path index backing real stack depth `d` (1-based depth; root is 0).
    func pathIndex(forDepth d: Int) -> Int? {
        let idx = d - 1 - nativeExtra
        guard idx >= 0 else { return nil }
        return idx
    }
}

private struct BackportRouterKey: EnvironmentKey {
    static let defaultValue: BackportNavRouter? = nil
}

extension EnvironmentValues {
    var backportNavRouter: BackportNavRouter? {
        get { self[BackportRouterKey.self] }
        set { self[BackportRouterKey.self] = newValue }
    }
}

// MARK: - NavigationStack

/// Backport of SwiftUI's `NavigationStack` usable on iOS 15.
///
/// Implemented on top of `NavigationView(.stack)` plus a hidden isActive link
/// chain that mirrors the path. Value-based links push through the router;
/// native `NavigationLink { destination }` links keep working natively and are
/// reconciled through the UINavigationController delegate.
public struct NavigationStack<Content: View>: View {
    @StateObject private var ownedRouter = BackportNavRouter()
    private let pathBinding: Binding<NavigationPath>?
    private let content: Content

    public init(path: Binding<NavigationPath>, @ViewBuilder content: () -> Content) {
        self.pathBinding = path
        self.content = content()
    }

    public init(@ViewBuilder content: () -> Content) {
        self.pathBinding = nil
        self.content = content()
    }

    public var body: some View {
        NavigationView {
            content
                .background(BackportNavSync(router: router))
                .background(BackportNavChain())
                .environment(\.backportNavRouter, router)
                .environmentObject(router)
                .onPreferenceChange(BackportDestinationsKey.self) { router.destinations = $0 }
                .onChange(of: pathBinding?.wrappedValue ?? ownedPath) { newPath in
                    router.pathChangedExternally(newPath)
                }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            router.configure(pathBinding: pathBinding)
            router.syncInitial()
        }
    }

    private var router: BackportNavRouter {
        // The owned router backs pathless stacks; for path-based stacks the
        // router is still owned here and simply mirrors the binding.
        ownedRouter
    }
}

// MARK: - Hidden chain

/// The hidden isActive NavigationLink chain that realizes programmatic
/// (path-based) pushes on top of NavigationView.
struct BackportNavChain: View {
    @EnvironmentObject private var router: BackportNavRouter

    var body: some View {
        BackportNavChainLevel(router: router, depth: 1)
    }
}

struct BackportNavChainLevel: View {
    let router: BackportNavRouter
    let depth: Int

    var body: some View {
        if depth <= 32 {
            NavigationLink(isActive: isActiveBinding) {
                ZStack {
                    if let idx = router.pathIndex(forDepth: depth) {
                        router.destinationView(pathIndex: idx)
                            .id(chainIdentity(depth: depth))
                    } else {
                        Color.clear
                    }
                    BackportNavChainLevel(router: router, depth: depth + 1)
                }
            } label: {
                Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            }
            .buttonStyle(.plain)
        }
    }

    private func chainIdentity(depth: Int) -> String {
        // Re-render the destination when the value behind it changes.
        let p = router.path
        let idx = depth - 1 - router.nativeExtra
        if p.elements.indices.contains(idx) {
            return "\(depth)-\(String(describing: type(of: p.elements[idx].base)))-\(idx)-\(p.elements.count)"
        }
        return "empty-\(depth)"
    }

    private var isActiveBinding: Binding<Bool> {
        Binding<Bool>(
            get: { router.depth >= depth },
            set: { active in
                // Pushes are driven by router.depth; interactive pops are
                // reconciled by the UINavigationController delegate proxy.
                // Nothing to do here beyond defensive convergence.
                if !active, router.depth >= depth {
                    // Delegate will reconcile; keep state coherent meanwhile.
                }
            }
        )
    }
}

// MARK: - UINavigationController sync + delegate proxy

/// Finds the enclosing UINavigationController, installs a delegate proxy and
/// reconciles actual stack depth with the router.
struct BackportNavSync: UIViewRepresentable {
    @ObservedObject var router: BackportNavRouter

    final class SyncView: UIView {
        var router: BackportNavRouter?
        weak var navigationController: UINavigationController?
        var proxy: BackportNavDelegateProxy?
    }

    final class BackportNavDelegateProxy: NSObject, UINavigationControllerDelegate {
        weak var original: UINavigationControllerDelegate?
        var onDidShow: (UINavigationController, UIViewController) -> Void = { _, _ in }

        func navigationController(_ navigationController: UINavigationController,
                                  willShow viewController: UIViewController,
                                  animated: Bool) {
            original?.navigationController?(navigationController, willShow: viewController, animated: animated)
        }

        func navigationController(_ navigationController: UINavigationController,
                                  didShow viewController: UIViewController,
                                  animated: Bool) {
            original?.navigationController?(navigationController, didShow: viewController, animated: animated)
            onDidShow(navigationController, viewController)
        }

        func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
            original?.navigationControllerSupportedInterfaceOrientations?(navigationController) ?? .all
        }

        func navigationControllerPreferredInterfaceOrientationForPresentation(_ navigationController: UINavigationController) -> UIInterfaceOrientation {
            original?.navigationControllerPreferredInterfaceOrientationForPresentation?(navigationController) ?? .portrait
        }
    }

    func makeUIView(context: Context) -> SyncView {
        let view = SyncView()
        view.router = router
        return view
    }

    func updateUIView(_ view: SyncView, context: Context) {
        view.router = router
        if view.navigationController == nil || view.navigationController?.delegate == nil {
            attachIfPossible(view)
        }
        // Initial reconcile in case the path was written before attach.
        DispatchQueue.main.async { [weak view] in
            guard let view, let nav = view.navigationController else { return }
            view.router?.reconcile(actualDepth: nav.viewControllers.count - 1)
        }
    }

    private func attachIfPossible(_ view: SyncView) {
        guard view.proxy == nil else { return }
        // Walk the responder chain to the nearest view controller, then use
        // its navigationController.
        var responder: UIResponder? = view
        var hostingVC: UIViewController?
        while let r = responder {
            if let vc = r as? UIViewController {
                hostingVC = vc
                break
            }
            responder = r.next
        }
        guard let nav = hostingVC?.navigationController else { return }
        let proxy = BackportNavDelegateProxy()
        proxy.original = nav.delegate
        proxy.onDidShow = { [weak view] navController, _ in
            guard let view else { return }
            view.router?.reconcile(actualDepth: navController.viewControllers.count - 1)
        }
        nav.delegate = proxy
        view.proxy = proxy
        view.navigationController = nav
    }
}

// MARK: - NavigationLink

/// Backport of `NavigationLink` covering the forms the app uses. Shadows
/// SwiftUI's type so the iOS 16-only `value:` initializer resolves on iOS 15.
/// - `NavigationLink(value:label:)` (iOS 16+): routed through the backport
///   NavigationStack so it works on iOS 15.
/// - `NavigationLink { destination } label:` and
///   `NavigationLink(isActive:) { destination } label:`: delegate to SwiftUI's
///   real implementation (available since iOS 13/15).
public struct NavigationLink<D: View, Label: View>: View {
    @Environment(\.backportNavRouter) private var router

    private let value: AnyHashable?
    private let destination: D?
    private let isActive: Binding<Bool>?
    private let label: Label

    /// Trailing-destination form — delegates to SwiftUI's NavigationLink.
    public init(@ViewBuilder destination: () -> D, @ViewBuilder label: () -> Label) {
        self.value = nil
        self.destination = destination()
        self.isActive = nil
        self.label = label()
    }

    /// isActive form — delegates to SwiftUI's NavigationLink (deprecated by
    /// Apple on iOS 16 but functional on every OS this backport supports).
    public init(isActive: Binding<Bool>, @ViewBuilder destination: () -> D, @ViewBuilder label: () -> Label) {
        self.value = nil
        self.destination = destination()
        self.isActive = isActive
        self.label = label()
    }

    public var body: some View {
        if let value {
            valueLinkBody(value)
        } else if let destination, let isActive {
            SwiftUI.NavigationLink(isActive: isActive) {
                destination
            } label: {
                label
            }
        } else if let destination {
            SwiftUI.NavigationLink {
                destination
            } label: {
                label
            }
        } else {
            label
        }
    }

    @ViewBuilder
    private func valueLinkBody(_ value: AnyHashable) -> some View {
        if let router {
            if isEmptyLabel {
                // Invisible tap target (the classic hidden-NavigationLink
                // overlay/background pattern): fills offered space, no chrome.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { router.push(value) }
                    .accessibilityHidden(true)
            } else {
                Button {
                    router.push(value)
                } label: {
                    label
                }
                .buttonStyle(.plain)
            }
        } else {
            // Outside any backport stack: fall back to the real link, which is
            // the correct behavior on iOS 16+ and inert on iOS 15.
            SwiftUI.NavigationLink {
                EmptyView()
            } label: {
                label
            }
                .opacity(0)
        }
    }

    private var isEmptyLabel: Bool {
        label is EmptyView
    }
}

extension NavigationLink where D == EmptyView {
    /// Value-based form: pushes through the backport router (iOS 15+).
    public init<V: Hashable>(value: V, @ViewBuilder label: () -> Label) {
        self.value = AnyHashable(value)
        self.destination = nil
        self.isActive = nil
        self.label = label()
    }
}
