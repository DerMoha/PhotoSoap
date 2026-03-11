import SwiftUI

struct FilterSheet: View {
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
                        Text("Loading filters...")
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
                    Text("Select Photos")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
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
                    title: "All Photos",
                    subtitle: "Entire library",
                    count: nil,
                    isSelected: currentFilter.isAll
                )
            }
        }
    }

    private var yearsSection: some View {
        Section("By Year") {
            if availableYears.isEmpty {
                emptyRow(text: "No years available")
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
        Section("By Month") {
            if availableYears.isEmpty {
                emptyRow(text: "No months available")
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
                    emptyRow(text: "No months found")
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
        let albums = albums.filter { !$0.isSmartAlbum }

        return Section("Albums") {
            if albums.isEmpty {
                emptyRow(text: "No albums found")
            } else {
                ForEach(albums) { album in
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

        return Section("Smart Albums") {
            if smartAlbums.isEmpty {
                emptyRow(text: "No smart albums found")
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
            return monthNameFormatter.string(from: date)
        }
        return "Month \(month)"
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

    private var monthNameFormatter: DateFormatter {
        Self.monthNameFormatter
    }
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
