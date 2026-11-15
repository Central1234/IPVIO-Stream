import SwiftUI

/// Tabs on the iPhone; on wide screens (iPhone Duo inner display, iPad) the tab bar can become a sidebar.
@MainActor
struct RootView: View {
    @EnvironmentObject var library: Library

    var body: some View {
        Group {
            if library.sources.isEmpty {
                NavigationStack { AddSourceView(firstRun: true) }
            } else {
                TabView {
                    Tab("Live TV", systemImage: "tv") { NavigationStack { LiveView() } }
                    Tab("Movies", systemImage: "film") { NavigationStack { VODView(kind: .movie) } }
                    Tab("Series", systemImage: "square.stack") { NavigationStack { VODView(kind: .series) } }
                    Tab("Search", systemImage: "magnifyingglass", role: .search) { NavigationStack { SearchView() } }
                    Tab("Settings", systemImage: "gearshape") { NavigationStack { SettingsView() } }
                }
                .tabViewStyle(.sidebarAdaptable)
                .overlay { if library.loading && library.catalog.isEmpty { LoadingView() } }
            }
        }
        .background(Theme.navy.ignoresSafeArea())
        .task { if library.catalog.isEmpty && library.active != nil { await library.reload() } }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Loading playlist …").foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.navy.opacity(0.92))
    }
}

/// Shown when a list is empty: the load error with a retry button, or a neutral hint.
@MainActor
struct EmptyStateView: View {
    @EnvironmentObject var library: Library
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: library.error == nil ? "tray" : "exclamationmark.triangle")
                .font(.system(size: 40)).foregroundStyle(Theme.muted)
            Text(library.error ?? text).multilineTextAlignment(.center).foregroundStyle(Theme.muted)
            if library.error != nil {
                Button("Try again") { Task { await library.reload() } }.buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
