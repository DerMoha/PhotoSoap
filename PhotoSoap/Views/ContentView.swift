import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var statsArray: [UserStats]
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @StateObject private var gameificationService = GameificationService()
    @State private var selectedTab = 0

    private var stats: UserStats {
        if let existingStats = statsArray.first {
            return existingStats
        } else {
            let newStats = UserStats()
            modelContext.insert(newStats)
            return newStats
        }
    }

    var body: some View {
        Group {
            if photoLibraryService.authorizationStatus == .notDetermined {
                PermissionRequestView(photoLibraryService: photoLibraryService)
            } else if photoLibraryService.authorizationStatus == .denied ||
                      photoLibraryService.authorizationStatus == .restricted {
                PermissionDeniedView()
            } else {
                mainTabView
            }
        }
        .onAppear {
            initializeStats()
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            PhotoReviewView(
                photoLibraryService: photoLibraryService,
                gameificationService: gameificationService,
                stats: stats
            )
            .tabItem {
                Label("Review", systemImage: "photo.stack")
            }
            .tag(0)

            StatsView(stats: stats, gameificationService: gameificationService)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
                .tag(1)

            AchievementsView(stats: stats, gameificationService: gameificationService)
                .tabItem {
                    Label("Achievements", systemImage: "trophy")
                }
                .tag(2)
        }
    }

    private func initializeStats() {
        gameificationService.updateDailyStreak(stats: stats)
        gameificationService.ensureDailyChallengeIsSet(stats: stats)
    }
}

struct PermissionRequestView: View {
    @ObservedObject var photoLibraryService: PhotoLibraryService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Photo Library Access")
                .font(.title)
                .fontWeight(.bold)

            Text("PhotoSoap needs access to your photo library to help you review and organize your photos.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task {
                    await photoLibraryService.requestAuthorization()
                }
            } label: {
                Text("Allow Access")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 80))
                .foregroundStyle(.orange)

            Text("Access Denied")
                .font(.title)
                .fontWeight(.bold)

            Text("PhotoSoap needs photo library access to work. Please enable it in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserStats.self, inMemory: true)
}
