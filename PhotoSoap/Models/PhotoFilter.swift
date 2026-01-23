import Foundation

enum PhotoFilter: Equatable, Hashable {
    case all
    case album(identifier: String, title: String)
    case year(Int)
    case month(year: Int, month: Int)

    var displayName: String {
        switch self {
        case .all:
            return "All Photos"
        case .album(_, let title):
            return title
        case .year(let year):
            return String(year)
        case .month(let year, let month):
            let monthName = Self.monthName(for: month)
            return "\(monthName) \(year)"
        }
    }

    var id: String {
        switch self {
        case .all:
            return "all"
        case .album(let identifier, _):
            return "album:\(identifier)"
        case .year(let year):
            return "year:\(year)"
        case .month(let year, let month):
            return "month:\(year)-\(month)"
        }
    }

    var isAll: Bool {
        if case .all = self {
            return true
        }
        return false
    }

    private static func monthName(for month: Int) -> String {
        let clampedMonth = max(1, min(month, 12))
        var components = DateComponents()
        components.year = 2000
        components.month = clampedMonth
        if let date = Calendar.current.date(from: components) {
            return monthNameFormatter.string(from: date)
        }
        return "Month \(month)"
    }

    private static let monthNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()
}
