import Foundation
import SwiftUI

@MainActor
final class ReviewFeedbackController {
    private let hapticsService: HapticsService
    private var hasTriggeredSwipeThresholdFeedback = false
    private var lastCelebrationFeedbackDate = Date.distantPast

    let celebrationFeedbackCooldown: TimeInterval = 0.75

    init(hapticsService: HapticsService) {
        self.hapticsService = hapticsService
    }

    func updateSwipeFeedback(distance: CGFloat, overlayThreshold: CGFloat, actionThreshold: CGFloat) {
        if distance < overlayThreshold {
            hasTriggeredSwipeThresholdFeedback = false
        } else if distance >= actionThreshold {
            if !hasTriggeredSwipeThresholdFeedback {
                hapticsService.selection()
                hasTriggeredSwipeThresholdFeedback = true
            }
        } else {
            hasTriggeredSwipeThresholdFeedback = false
        }
    }

    func resetSwipeFeedback() {
        hasTriggeredSwipeThresholdFeedback = false
    }

    func triggerCelebrationIfNeeded(now: Date = Date()) {
        guard now.timeIntervalSince(lastCelebrationFeedbackDate) > celebrationFeedbackCooldown else { return }

        lastCelebrationFeedbackDate = now
        hapticsService.success()
    }
}
