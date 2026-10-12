import SwiftUI

@main
struct SequenceIOSApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                IOSTodayView()
                    .tabItem { Label("今日", systemImage: "sun.max") }
                IOSCategoriesView()
                    .tabItem { Label("分类", systemImage: "tag") }
            }
                .environmentObject(store)
                .tint(AppColors.brand)
        }
    }
}
