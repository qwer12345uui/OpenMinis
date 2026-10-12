import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - PhotosPicker (iOS 16 backport)
//
// Backport of SwiftUI's PhotosPicker surface (iOS 16+): the
// `.photosPicker(isPresented:selection:matching:)` modifier, the
// `PhotosPickerItem` type and `loadTransferable(type:)`. Implemented on top of
// PHPickerViewController (iOS 14+), so it behaves consistently on iOS 15 and
// on every newer OS.

// MARK: - BackportTransferable

/// Loader protocol used by the backport `PhotosPickerItem`. Types that were
/// `Transferable` (iOS 16+) implement this instead; the app's
/// `VideoFileTransferable` conforms to it (see ChatInputBar.swift).
public protocol BackportTransferable {
    static func backportLoad(from provider: NSItemProvider) async throws -> Self?
}

extension Data: BackportTransferable {
    public static func backportLoad(from provider: NSItemProvider) async throws -> Data? {
        if let data = try? await provider.loadDataRepresentation() {
            return data
        }
        // Some providers only expose a concrete type identifier.
        let identifiers = provider.registeredTypeIdentifiers
        guard let first = identifiers.first else { return nil }
        return try await provider.loadDataRepresentation(forTypeIdentifier: first)
    }
}

extension UIImage: BackportTransferable {
    public static func backportLoad(from provider: NSItemProvider) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
                _ = error
            }
        }
    }
}

extension URL: BackportTransferable {
    public static func backportLoad(from provider: NSItemProvider) async throws -> URL? {
        try await backportLoadFile(from: provider, preferredTypes: provider.registeredTypeIdentifiers)
    }

    static func backportLoadFile(from provider: NSItemProvider, preferredTypes: [String]) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            let matched = preferredTypes.first { provider.hasItemConformingToTypeIdentifier($0) }
            guard let matched else {
                continuation.resume(returning: nil)
                return
            }
            _ = provider.loadFileRepresentation(forTypeIdentifier: matched) { url, error in
                guard let url, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                // Copy out of the provider's temporary location.
                let target = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - PhotosPickerItem

/// Backport of SwiftUI's `PhotosPickerItem` (iOS 16+).
public struct PhotosPickerItem: Hashable, Identifiable {
    public let id: UUID
    public let provider: NSItemProvider

    init(provider: NSItemProvider) {
        self.id = UUID()
        self.provider = provider
    }

    public static func == (lhs: PhotosPickerItem, rhs: PhotosPickerItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Backport of `loadTransferable(type:)`. Works with `Data`, `UIImage`,
    /// `URL` and any type conforming to `BackportTransferable`.
    public func loadTransferable<T: BackportTransferable>(type: T.Type) async throws -> T? {
        try await T.backportLoad(from: provider)
    }
}

// MARK: - photosPicker modifier

public extension View {
    /// Backport of `.photosPicker(isPresented:selection:matching:)`
    /// (multi-selection form, iOS 16+).
    func photosPicker(isPresented: Binding<Bool>,
                      selection: Binding<[PhotosPickerItem]>,
                      matching filter: PHPickerFilter? = nil,
                      preferredItemEncoding: PhotosPickerItemEncoding? = nil) -> some View {
        background(
            Color.clear.sheet(isPresented: isPresented) {
                BackportPHPickerSheet(
                    mode: .multi(selection),
                    filter: filter,
                    preferredItemEncoding: preferredItemEncoding,
                    onDismiss: { isPresented.wrappedValue = false }
                )
            }
        )
    }

    /// Backport of `.photosPicker(isPresented:selection:matching:)`
    /// (single-selection form, iOS 16+).
    func photosPicker(isPresented: Binding<Bool>,
                      selection: Binding<PhotosPickerItem?>,
                      matching filter: PHPickerFilter? = nil,
                      preferredItemEncoding: PhotosPickerItemEncoding? = nil) -> some View {
        background(
            Color.clear.sheet(isPresented: isPresented) {
                BackportPHPickerSheet(
                    mode: .single(selection),
                    filter: filter,
                    preferredItemEncoding: preferredItemEncoding,
                    onDismiss: { isPresented.wrappedValue = false }
                )
            }
        )
    }
}

/// Backport of `PhotosPickerItemEncoding` (iOS 16+).
public struct PhotosPickerItemEncoding: Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let automatic = PhotosPickerItemEncoding(rawValue: 0)
    public static let compatible = PhotosPickerItemEncoding(rawValue: 1)
    public static let current = PhotosPickerItemEncoding(rawValue: 2)
}

// MARK: - Sheet

struct BackportPHPickerSheet: UIViewControllerRepresentable {
    enum Mode {
        case multi(Binding<[PhotosPickerItem]>)
        case single(Binding<PhotosPickerItem?>)
    }

    let mode: Mode
    let filter: PHPickerFilter?
    let preferredItemEncoding: PhotosPickerItemEncoding?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = filter
        switch mode {
        case .multi: config.selectionLimit = 10
        case .single: config.selectionLimit = 1
        }
        switch preferredItemEncoding {
        case .compatible: config.preferredAssetRepresentationMode = .compatible
        case .current: config.preferredAssetRepresentationMode = .current
        default: config.preferredAssetRepresentationMode = .automatic
        }
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: BackportPHPickerSheet

        init(_ parent: BackportPHPickerSheet) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let items = results.map { PhotosPickerItem(provider: $0.itemProvider) }
            switch parent.mode {
            case .multi(let binding):
                binding.wrappedValue = items
            case .single(let binding):
                binding.wrappedValue = items.first
            }
            parent.onDismiss()
        }
    }
}
