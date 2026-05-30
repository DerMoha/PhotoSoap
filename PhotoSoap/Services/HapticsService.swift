import Foundation
import UIKit
import Combine

struct HapticsPerformer {
    let impact: (UIImpactFeedbackGenerator.FeedbackStyle) -> Void
    let success: () -> Void
    let error: () -> Void
    let warning: () -> Void
    let selection: () -> Void

    @MainActor
    static var live: HapticsPerformer {
        HapticsPerformer(
            impact: { style in Haptic.impact(style) },
            success: { Haptic.success() },
            error: { Haptic.error() },
            warning: { Haptic.warning() },
            selection: { Haptic.selection() }
        )
    }
}

@MainActor
final class HapticsService: ObservableObject {
    static let hapticsEnabledKey = "isHapticsEnabled"

    @Published private(set) var isEnabled: Bool

    private let defaults: UserDefaults
    private let performer: HapticsPerformer

    init(defaults: UserDefaults = .standard, performer: HapticsPerformer? = nil) {
        self.defaults = defaults
        self.performer = performer ?? .live
        self.isEnabled = defaults.object(forKey: Self.hapticsEnabledKey) as? Bool ?? true
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        defaults.set(isEnabled, forKey: Self.hapticsEnabledKey)
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard isEnabled else { return }
        performer.impact(style)
    }

    func success() {
        guard isEnabled else { return }
        performer.success()
    }

    func error() {
        guard isEnabled else { return }
        performer.error()
    }

    func warning() {
        guard isEnabled else { return }
        performer.warning()
    }

    func selection() {
        guard isEnabled else { return }
        performer.selection()
    }
}
