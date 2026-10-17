import SwiftUI
import UIKit
import UserNotifications

// MARK: - App icon badge

/// iOS 15 fallback for `UNUserNotificationCenter.setBadgeCount(_:completionHandler:)`
/// (iOS 16+). On iOS 15 the legacy `applicationIconBadgeNumber` is used.
public enum BackportBadge {
    public static func set(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = max(0, count)
            }
        }
    }
}

// MARK: - Geometry observation

extension View {
    /// Backport of `View.onGeometryChange(for:of:action:)` (iOS 16+).
    ///
    /// On iOS 15 this falls back to a background `GeometryReader` that fires
    /// the action once on appear (matching the initial fire of the real API)
    /// and again whenever the transformed value changes.
    @ViewBuilder
    public func backportOnGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T) -> Void
    ) -> some View {
        if #available(iOS 16.0, *) {
            self.onGeometryChange(for: T.self, of: transform, action: action)
        } else {
            self.background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { action(transform(proxy)) }
                        .onChange(of: transform(proxy)) { newValue in
                            action(newValue)
                        }
                }
            )
        }
    }
}

// MARK: - iOS 16 feature placeholder

/// Shown in place of a sheet whose real content needs iOS 16+ APIs. Keeps the
/// sheet callable on iOS 15 instead of forcing the whole call site to be
/// unavailable.
public struct IOS16FeatureUnavailableView: View {
    let feature: String

    public init(_ feature: String) {
        self.feature = feature
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(feature)
                .font(.headline)
            Text("This sign-in flow needs iOS 16 or newer. You can still paste a token manually on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
