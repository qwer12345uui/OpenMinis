import Foundation

/// Reads and writes PendingShare data to the App Group shared container.
/// Compiled into both the main app target and the Share Extension target.
enum SharedContainerStore {
    static let appGroupID = "group.com.openminis.app"

    private static let pendingShareKey = "pendingShare"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Directory in the shared container for transferring attachment files.
    static var sharedFileDirectory: URL? {
        containerURL.appendingPathComponent("ShareExtension", isDirectory: true)
    }

    /// The App Group container, with a fallback for builds whose signature does
    /// not carry the App Group entitlement.
    ///
    /// [T-ios-appgroup-optional] Unsigned builds that get re-signed on a device
    /// (AltStore / Sideloadly / personal provisioning profiles) do not have
    /// `com.apple.security.application-groups`, so
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil.
    /// Callers used to force-unwrap it, which trapped at launch — the app
    /// flashed the launch screen and quit. Falling back to a directory inside
    /// the app's own container keeps the app usable; only the Files-app /
    /// cross-process sharing degrades.
    static var containerURL: URL {
        let fm = FileManager.default
        if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let fallback = base.appendingPathComponent("AppGroupFallback", isDirectory: true)
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    // MARK: - Write (called by Share Extension)

    static func savePendingShare(_ share: PendingShare) {
        guard let defaults = sharedDefaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(share) {
            defaults.set(data, forKey: pendingShareKey)
            defaults.synchronize()
        }
    }

    // MARK: - Read & Consume (called by main app)

    static func loadPendingShare() -> PendingShare? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: pendingShareKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingShare.self, from: data)
    }

    static func clearPendingShare() {
        sharedDefaults?.removeObject(forKey: pendingShareKey)
        sharedDefaults?.synchronize()
    }

    /// Remove all files from the shared transfer directory.
    static func cleanSharedFiles() {
        guard let dir = sharedFileDirectory else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }
}
