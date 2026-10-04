import SwiftUI
import SwiftData

struct FilterSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var hapticsService: HapticsService
    @AppStorage(UserDefaultsKeys.filterHideFavorites) private var hidesFavorites = true
    @AppStorage(UserDefaultsKeys.reviewSortOrder) private var sortOrder: ReviewSortOrder = .random

    @ObservedObject var photoLibraryService: PhotoLibraryService
    let currentFilter: PhotoFilter
    let currentMediaKind: ReviewMediaKind
    let onSelect: (PhotoFilter) -> Void
    let onMediaKindChange: (ReviewMediaKind) -> Void
    let onHidesFavoritesChange: (Bool) -> Void
    let onSortOrderChange: (ReviewSortOrder) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reviewProgress = ReviewCalendarProgress()
    @State private var monthsByYear: [Int: [Int]] = [:]
    @State private var loadError: String?
    @State private var loadID = UUID()
    @State private var albums: [AlbumInfo] = []
    @State private var availableYears: [Int] = []
    @State private var availableMonths: [Int] = []
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var selectedMediaKind: ReviewMediaKind = .photos
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label(String(localized: "filter.progress.error", defaultValue: "Couldn’t Load Progress", table: "LocalizableFilter"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button(String(localized: "filter.progress.retry", defaultValue: "Try Again", table: "LocalizableFilter")) {
                            Task { await loadData() }
                        }
                    }
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "filter.loading", table: "LocalizableFilter"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        mediaKindSection
                        favoritesSection
                        sortOrderSection
                        allPhotosSection
                        yearsSection
                        monthsSection
                        albumsSection
                        smartAlbumsSection
                    }
                }
            }
            .navigationTitle(String(localized: "filter.title", table: "LocalizableFilter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done", table: "LocalizableShared")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            switch currentFilter {
            case .year(let year), .month(let year, _): selectedYear = year
            default: break
            }
            selectedMediaKind = currentMediaKind
            await loadData()
        }
        .onChange(of: selectedMediaKind) { _, mediaKind in
            hapticsService.selection()
            onMediaKindChange(mediaKind)

            Task {
                await loadData()
            }
        }
        .onChange(of: hidesFavorites) { _, hidesFavorites in
            hapticsService.selection()
            onHidesFavoritesChange(hidesFavorites)

            Task {
                await loadData()
            }
        }
        .onChange(of: sortOrder) { _, order in
            hapticsService.selection()
            onSortOrderChange(order)
        }
    }

    private var mediaKindSection: some View {
        Section(String(localized: "filter.media", defaultValue: "Media", table: "LocalizableFilter")) {
            Picker(String(localized: "filter.media", defaultValue: "Media", table: "LocalizableFilter"), selection: $selectedMediaKind) {
                ForEach(ReviewMediaKind.allCases) { mediaKind in
                    Label(mediaKind.displayName, systemImage: symbolName(for: mediaKind))
                        .tag(mediaKind)
                }
            }
            .pickerStyle(.segmented)

            Text(mediaHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var favoritesSection: some View {
        Section {
            Toggle(isOn: $hidesFavorites) {
                Label(String(localized: "filter.favorites.hide", defaultValue: "Hide Favorites", table: "LocalizableFilter"), systemImage: "heart.fill")
            }
        } footer: {
            Text(String(localized: "filter.favorites.help", defaultValue: "Favorites are hidden from all review filters. Turn this off to include them.", table: "LocalizableFilter"))
        }
    }

    private var sortOrderSection: some View {
        Section(String(localized: "filter.order", defaultValue: "Order", table: "LocalizableFilter")) {
            Picker(String(localized: "filter.order", defaultValue: "Order", table: "LocalizableFilter"), selection: $sortOrder) {
                Text(String(localized: "filter.order.random", defaultValue: "Random", table: "LocalizableFilter"))
                    .tag(ReviewSortOrder.random)
                Text(String(localized: "filter.order.newestFirst", defaultValue: "Newest First", table: "LocalizableFilter"))
                    .tag(ReviewSortOrder.newestFirst)
                Text(String(localized: "filter.order.oldestFirst", defaultValue: "Oldest First", table: "LocalizableFilter"))
                    .tag(ReviewSortOrder.oldestFirst)
            }
            .pickerStyle(.segmented)
        }
    }

    private var allPhotosSection: some View {
        Section {
            Button {
                selectFilter(.all)
            } label: {
                FilterRow(
                    title: selectedMediaKind.allFilterTitle,
                    subtitle: selectedMediaKind.libraryDescription,
                    count: nil,
                    isSelected: currentFilter.isAll
                )
            }
        }
    }

    private var yearsSection: some View {
        Section(String(localized: "filter.byYear", defaultValue: "By Year", table: "LocalizableFilter")) {
            if displayedYears.isEmpty {
                emptyRow(text: String(localized: "filter.noYears", defaultValue: "No years available", table: "LocalizableFilter"))
            } else {
                ForEach(displayedYears, id: \.self) { year in
                    Button {
                        selectFilter(.year(year))
                    } label: {
                        FilterRow(
                            title: String(year),
                            subtitle: nil,
                            count: nil,
                            isSelected: currentFilter == .year(year),
                            progress: reviewProgress.progress(for: year)
                        )
                    }
                }
            }
        }
    }

    private var monthsSection: some View {
        Section(String(localized: "filter.byMonth", defaultValue: "By Month", table: "LocalizableFilter")) {
            if displayedYears.isEmpty {
                emptyRow(text: String(localized: "filter.noMonths", defaultValue: "No months available", table: "LocalizableFilter"))
            } else {
                Picker(String(localized: "filter.year", defaultValue: "Year", table: "LocalizableFilter"), selection: $selectedYear) {
                    ForEach(displayedYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedYear) { _, newValue in
                    availableMonths = monthsByYear[newValue] ?? []
                }

                if displayedMonths.isEmpty {
                    emptyRow(text: String(localized: "filter.noMonths", table: "LocalizableFilter"))
                } else {
                    ForEach(displayedMonths, id: \.self) { month in
                        let filter = PhotoFilter.month(year: selectedYear, month: month)
                        Button {
                            selectFilter(filter)
                        } label: {
                            FilterRow(
                                title: monthName(for: month),
                                subtitle: String(selectedYear),
                                count: nil,
                                isSelected: currentFilter == filter,
                                progress: reviewProgress.monthsByYear[selectedYear]?[month]
                            )
                        }
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        let userAlbums = albums.filter { !$0.isSmartAlbum }

        return Section(String(localized: "filter.albums", defaultValue: "Albums", table: "LocalizableFilter")) {
            if userAlbums.isEmpty {
                emptyRow(text: String(localized: "filter.noAlbums", defaultValue: "No albums available", table: "LocalizableFilter"))
            } else {
                ForEach(userAlbums) { album in
                    let filter = PhotoFilter.album(identifier: album.id, title: album.title)
                    Button {
                        selectFilter(filter)
                    } label: {
                        FilterRow(
                            title: album.title,
                            subtitle: nil,
                            count: album.count,
                            isSelected: currentFilter == filter
                        )
                    }
                }
            }
        }
    }

    private var smartAlbumsSection: some View {
        let smartAlbums = albums.filter { $0.isSmartAlbum }

        return Section(String(localized: "filter.smartAlbums", defaultValue: "Smart Albums", table: "LocalizableFilter")) {
            if smartAlbums.isEmpty {
                emptyRow(text: String(localized: "filter.noAlbums", defaultValue: "No albums available", table: "LocalizableFilter"))
            } else {
                ForEach(smartAlbums) { album in
                    let filter = PhotoFilter.album(identifier: album.id, title: album.title)
                    Button {
                        selectFilter(filter)
                    } label: {
                        FilterRow(
                            title: album.title,
                            subtitle: nil,
                            count: album.count,
                            isSelected: currentFilter == filter
                        )
                    }
                }
            }
        }
    }

    private func selectFilter(_ filter: PhotoFilter) {
        hapticsService.selection()
        onSelect(filter)
        dismiss()
    }

    private func loadData() async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        loadError = nil
        let reviewedIDs: Set<String>
        do {
            reviewedIDs = Set(try modelContext.fetch(FetchDescriptor<ReviewedPhoto>()).map(\.id))
        } catch {
            loadError = error.localizedDescription
            isLoading = false
            return
        }
        let filterData = await photoLibraryService.loadFilterData(reviewedIDs: reviewedIDs)
        guard requestID == loadID else { return }
        reviewProgress = filterData.reviewProgress
        monthsByYear = filterData.availableMonthsByYear
        albums = filterData.albums
        availableYears = filterData.availableYears

        if let firstYear = availableYears.first {
            if !availableYears.contains(selectedYear) {
                selectedYear = firstYear
            }
            availableMonths = filterData.availableMonthsByYear[selectedYear] ?? []
        } else {
            availableMonths = []
        }

        isLoading = false
    }

    private var mediaHelpText: String {
        switch selectedMediaKind {
        case .photos:
            return String(localized: "filter.media.photos.help", defaultValue: "Start with photos. Switch when you want to review videos.", table: "LocalizableFilter")
        case .videos:
            return String(localized: "filter.media.videos.help", defaultValue: "Review only videos from the same filters.", table: "LocalizableFilter")
        case .all:
            return String(localized: "filter.media.all.help", defaultValue: "Mix photos and videos in one review pass.", table: "LocalizableFilter")
        }
    }

    private func symbolName(for mediaKind: ReviewMediaKind) -> String {
        switch mediaKind {
        case .photos:
            return "photo"
        case .videos:
            return "play.rectangle"
        case .all:
            return "square.grid.2x2"
        }
    }

    private var displayedYears: [Int] {
        sortOrder == .oldestFirst ? availableYears.sorted() : availableYears.sorted(by: >)
    }

    private var displayedMonths: [Int] {
        sortOrder == .oldestFirst ? availableMonths.sorted() : availableMonths.sorted(by: >)
    }

    private func monthName(for month: Int) -> String {
        let clampedMonth = max(1, min(month, 12))
        var components = DateComponents()
        components.year = 2000
        components.month = clampedMonth
        if let date = Calendar.current.date(from: components) {
            return Self.monthNameFormatter.string(from: date)
        }
        return String(localized: "filter.month", defaultValue: "Month \(month)", table: "LocalizableFilter").replacingOccurrences(of: "%d", with: "\(month)")
    }

    private func emptyRow(text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
    }

    private static let monthNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()
}

private struct FilterRow: View {
    let title: String
    let subtitle: String?
    let count: Int?
    let isSelected: Bool
    var progress: ReviewMonthProgress? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)

                if let progress {
                    ProgressView(value: progress.fraction)
                        .tint(progress.isComplete ? .green : .blue)
                    Text(String(format: String(localized: "filter.progress.count", defaultValue: "%d of %d reviewed", table: "LocalizableFilter"), progress.reviewedCount, progress.totalCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let progress {
                VStack(spacing: 4) {
                    Text(progress.displayFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    if progress.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    FilterSheet(
        photoLibraryService: PhotoLibraryService(),
        currentFilter: .all,
        currentMediaKind: .photos,
        onSelect: { _ in },
        onMediaKindChange: { _ in },
        onHidesFavoritesChange: { _ in },
        onSortOrderChange: { _ in }
    )
    .modelContainer(for: ReviewedPhoto.self, inMemory: true)
    .environmentObject(HapticsService())
}
