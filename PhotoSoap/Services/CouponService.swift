import Foundation
import CryptoKit

enum CouponRedemptionResult: Equatable {
    case success
    case alreadyRedeemed
    case invalidCode
    case expiredCode
}

struct SignedCouponToken: Codable {
    let code: String
    let timestamp: UInt64
    let signature: String

    func isExpired(relativeTo now: Date = Date()) -> Bool {
        let thirtyDays: UInt64 = 30 * 24 * 60 * 60
        return now.timeIntervalSince1970 > TimeInterval(timestamp + thirtyDays)
    }
}

enum CouponService {
    private static let secretKey = SymmetricKey(data: Data("PhotoSoap-CouponSecret-v1".utf8))
    private static let compactAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let compactCodeLength = 8
    private static let compactDayModulo = 26 * 26
    private static let compactSignatureLength = 5
    private static let maxCouponAgeInDays = 30
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60

    static func validate(code: String, now: Date = Date()) -> CouponRedemptionResult {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return .invalidCode }

        if normalized.contains("-") {
            return validateLegacyToken(normalized, now: now)
        }

        return validateCompactToken(normalized, now: now)
    }

    static func generateToken(for code: String, now: Date = Date()) -> String? {
        let dayNumber = daysSinceReferenceDate(for: now)
        let variant = variantIndex(for: code)
        let dayPrefix = encodeBase26(dayNumber % compactDayModulo, length: 2)
        let variantCharacter = String(compactAlphabet[variant])
        let signature = compactSignature(dayNumber: dayNumber, variant: variant)

        return dayPrefix + variantCharacter + signature
    }

    static func generateLegacyToken(for code: String, now: Date) -> String {
        let timestamp = UInt64(now.timeIntervalSince1970)
        let message = "\(timestamp)-\(code)"

        let hmac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: secretKey)
        let signature = Data(hmac).base64EncodedString()

        return "\(timestamp)-\(code)-\(signature)"
    }

    private static func validateLegacyToken(_ normalized: String, now: Date) -> CouponRedemptionResult {
        let components = normalized.split(separator: "-").map(String.init)
        guard components.count == 3,
              let timestamp = UInt64(components[0]) else {
            return .invalidCode
        }

        let expectedSignature = components[2]
        let message = "\(timestamp)-\(components[1])"

        let expectedHMAC = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: secretKey)
        let expectedHMACString = Data(expectedHMAC).base64EncodedString()

        guard expectedHMACString == expectedSignature else {
            return .invalidCode
        }

        let token = SignedCouponToken(code: components[1], timestamp: timestamp, signature: expectedSignature)

        if token.isExpired(relativeTo: now) {
            return .expiredCode
        }

        return .success
    }

    private static func validateCompactToken(_ normalized: String, now: Date) -> CouponRedemptionResult {
        guard normalized.count == compactCodeLength,
              normalized.allSatisfy(\.isASCIIUppercase) else {
            return .invalidCode
        }

        guard let matchDay = matchingCompactDay(for: normalized, now: now) else {
            return .invalidCode
        }

        let currentDay = daysSinceReferenceDate(for: now)
        return currentDay - matchDay > maxCouponAgeInDays ? .expiredCode : .success
    }

    private static func matchingCompactDay(for normalized: String, now: Date) -> Int? {
        let characters = Array(normalized)
        let dayPrefix = String(characters.prefix(2))
        let variantCharacter = characters[2]
        let signature = String(characters.suffix(compactSignatureLength))

        guard let encodedDay = decodeBase26(dayPrefix),
              let variant = compactAlphabet.firstIndex(of: variantCharacter) else {
            return nil
        }

        let currentDay = daysSinceReferenceDate(for: now)
        let earliestCandidate = max(0, currentDay - compactDayModulo)

        for candidateDay in stride(from: currentDay, through: earliestCandidate, by: -1) {
            guard candidateDay % compactDayModulo == encodedDay else {
                continue
            }

            if compactSignature(dayNumber: candidateDay, variant: variant) == signature {
                return candidateDay
            }
        }

        return nil
    }

    private static func compactSignature(dayNumber: Int, variant: Int) -> String {
        let message = "compact-v1:\(dayNumber):\(variant)"
        let digest = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: secretKey)
        let value = digest.prefix(4).reduce(0) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }

        return encodeBase26(Int(value), length: compactSignatureLength)
    }

    private static func variantIndex(for code: String) -> Int {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            return 0
        }

        return normalized.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult + Int(scalar.value)) % compactAlphabet.count
        }
    }

    private static func daysSinceReferenceDate(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 / secondsPerDay)
    }

    private static func encodeBase26(_ value: Int, length: Int) -> String {
        var remaining = value
        var characters = Array(repeating: Character("A"), count: length)

        for index in stride(from: length - 1, through: 0, by: -1) {
            characters[index] = compactAlphabet[remaining % compactAlphabet.count]
            remaining /= compactAlphabet.count
        }

        return String(characters)
    }

    private static func decodeBase26(_ value: String) -> Int? {
        var result = 0

        for character in value {
            guard let index = compactAlphabet.firstIndex(of: character) else {
                return nil
            }

            result = (result * compactAlphabet.count) + index
        }

        return result
    }
}

private extension Character {
    var isASCIIUppercase: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }

        return scalar.value >= 65 && scalar.value <= 90
    }
}
