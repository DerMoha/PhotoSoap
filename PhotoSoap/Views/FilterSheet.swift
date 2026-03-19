import SwiftUI

struct FilterSheet: View {
    @EnvironmentObject private var hapticsService: HapticsService
    @ObservedObject var photoLibraryService: PhotoLibraryService
    let currentFilter: PhotoFilter
    let onSelect: (PhotoFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [AlbumInfo] = []
    @State private var availableYears: [Int] = []
    @State private var availableMonths: [Int] = []
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "filter.loading", table: "LocalizableFilter"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        allPhotosSection
                        yearsSection
                        monthsSection
                        albumsSection
                        smartAlbumsSection
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(String(localized: "filter.title", table: "LocalizableFilter"))
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done", table: "LocalizableShared")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadData()
        }
    }

    private var allPhotosSection: some View {
        Section {
            Button {
                selectFilter(.all)
            } label: {
                FilterRow(
                    title: String(localized: "filter.allPhotos", defaultValue: "All Photos", table: "LocalizableFilter"),
                    subtitle: String(localized: "filter.entireLibrary", defaultValue: "Your entire library", table: "LocalizableFilter"),
                    count: nil,
                    isSelected: currentFilter.isAll
                )
            }
        }
    }

    private var yearsSection: some View {
        Section(String(localized: "filter.byYear", defaultValue: "By Year", table: "LocalizableFilter")) {
            if availableYears.isEmpty {
                emptyRow(text: String(localized: "filter.noYears", defaultValue: "No years available", table: "LocalizableFilter"))
            } else {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        selectFilter(.year(year))
                    } label: {
                        FilterRow(
                            title: String(year),
                            subtitle: nil,
                            count: nil,
                            isSelected: currentFilter == .year(year)
                        )
                    }
                }
            }
        }
    }

    private var monthsSection: some View {
        Section(String(localized: "filter.byMonth", defaultValue: "By Month", table: "LocalizableFilter")) {
            if availableMonths.isEmpty {
                emptyRow(text: String(localized: "filter.noMonths", defaultValue: "No months available", table: "LocalizableFilter"))
            } else {
                Picker("Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedYear) { _, newValue in
                    availableMonths = photoLibraryService.getAvailableMonths(for: newValue)
                }

                if availableMonths.isEmpty {
                    emptyRow(text: String(localized: "filter.noMonths", table: "LocalizableFilter"))
                } else {
                    ForEach(availableMonths, id: \.self) { month in
                        let filter = PhotoFilter.month(year: selectedYear, month: month)
                        Button {
                            selectFilter(filter)
                        } label: {
                            FilterRow(
                                title: monthName(for: month),
                                subtitle: String(selectedYear),
                                count: nil,
                                isSelected: currentFilter == filter
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
        let filterData = await photoLibraryService.loadFilterData()
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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
        onSelect: { _ in }
    )
}
