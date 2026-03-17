import Foundation
import CryptoKit

enum CouponRedemptionResult {
    case success
    case alreadyRedeemed
    case invalidCode
}

enum CouponService {
    // To generate a hash for a new coupon code, run:
    //   echo -n "YOURCODEHERE" | shasum -a 256
    // Codes are normalized to uppercase before hashing.
    private static let validCodeHashes: Set<String> = [
        "0476d34fc74167e41ec7159f80e90b9207cbb5bd04c7bacb95a9e2e713cda87b",
        "3bb9af82233aebdf8ba976f5a32293f9d2ec102380085519e55d80a82444363a",
    ]

    static func validate(code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return false }

        let hash = SHA256.hash(data: Data(normalized.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return validCodeHashes.contains(hashString)
    }
}
