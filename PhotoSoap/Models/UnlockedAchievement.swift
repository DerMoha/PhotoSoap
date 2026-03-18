import Foundation
import SwiftData

@Model
class UnlockedAchievement {
    @Attribute(.unique) var achievementId: String
    var unlockDate: Date

    init(achievementId: String, unlockDate: Date = Date()) {
        self.achievementId = achievementId
        self.unlockDate = unlockDate
    }
}
