import Foundation
import CryptoKit

enum CouponRedemptionResult {
    case success
    case alreadyRedeemed
    case invalidCode
    case expiredCode
}

struct SignedCouponToken: Codable {
    let code: String
    let timestamp: UInt64
    let signature: String

    var isExpired: Bool {
        let thirtyDays: UInt64 = 30 * 24 * 60 * 60
        return Date().timeIntervalSince1970 > TimeInterval(timestamp + thirtyDays)
    }
}

enum CouponService {
    private static let secretKey = SymmetricKey(data: Data("PhotoSoap-CouponSecret-v1".utf8))

    static func validate(code: String) -> CouponRedemptionResult {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return .invalidCode }

        let components = normalized.split(separator: "-").map(String.init)
        guard components.count == 3,
              let timestamp = UInt64(components[0]),
              let _ = UInt64(components[1]) else {
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

        if token.isExpired {
            return .expiredCode
        }

        return .success
    }

    static func generateToken(for code: String) -> String? {
        let timestamp = UInt64(Date().timeIntervalSince1970)
        let message = "\(timestamp)-\(code)"

        let hmac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: secretKey)
        let signature = Data(hmac).base64EncodedString()

        return "\(timestamp)-\(code)-\(signature)"
    }
}
