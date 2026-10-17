import Foundation
import UIKit

#if MINIS_IOS15

// MARK: - iOS 15 build stubs
//
// The App Intents / Shortcuts layer (`Agent/Intents/*`) is compiled out of the
// iOS 15 build: AppIntents.framework does not exist there and a strong link
// would abort the process in dyld before any app code runs. A handful of
// symbols from that layer are referenced by code that still ships on iOS 15,
// so the same names are provided here with inert implementations.

extension Notification.Name {
    /// Same raw value as the App Intents version, so anything still posting or
    /// observing it keeps working.
    static let openSessionFromIntent = Notification.Name("openSessionFromIntent")
}

enum ShortcutNotification {
    static let categoryId = "SHORTCUT_TASK"

    static func post(id: String, title: String, body: String, sessionId: String) {
        // No App Intents on iOS 15 — nothing to notify about.
    }
}

/// Mirrors the store in `Agent/Intents/SendPromptIntent.swift` (which is
/// gated out of this build). Kept in sync behaviourally: the cold-launch path
/// consumes a buffered id at most once, and the warm path records when it
/// navigated so the launch-screen default can't override it.
final class NotificationNavigationStore {
    static let shared = NotificationNavigationStore()

    private var pendingSessionId: String?
    private var pendingSetAt: Date?
    private var handledAt: Date?

    func setPending(_ sessionId: String) {
        pendingSessionId = sessionId
        pendingSetAt = Date()
    }

    func takePending() -> String? {
        defer { pendingSessionId = nil; pendingSetAt = nil }
        guard let sid = pendingSessionId,
              let t = pendingSetAt,
              Date().timeIntervalSince(t) < 30 else { return nil }
        return sid
    }

    func markHandled() {
        pendingSessionId = nil
        pendingSetAt = nil
        handledAt = Date()
    }

    var handledRecently: Bool {
        guard let t = handledAt else { return false }
        return Date().timeIntervalSince(t) < 10
    }
}

/// Notification-tap delegate from the App Intents layer. On iOS 15 the
/// Shortcuts notifications are never posted, so registration is a no-op.
final class ShortcutNotificationDelegate: NSObject {
    static let shared = ShortcutNotificationDelegate()

    func register() {}
}

enum SendPromptResponseParsing {
    @MainActor
    static func extractResponseText(from vm: AIChatViewModel) -> String {
        guard let lastAssistant = vm.messages.last(where: { $0.role == .assistant && !$0.isInternalBridge }) else {
            return "No response."
        }
        let text = lastAssistant.blocks
            .filter { $0.kind == .text }
            .map { $0.content }
            .joined(separator: "\n")
        return text.isEmpty ? "No response." : text
    }
}

enum AudioTogglePlaybackBridge {
    static let darwinNotificationName = "com.openminis.app.liveActivity.audioToggle"
}

#endif
