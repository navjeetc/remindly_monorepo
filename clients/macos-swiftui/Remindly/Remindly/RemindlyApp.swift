import SwiftUI

@main
struct RemindlyApp: App {
    @StateObject private var vm = ReminderVM()
    
    init() {
        // Setup notification categories on app launch
        NotificationManager.shared.setupNotificationCategories()
    }
    
    var body: some Scene {
        WindowGroup {
            ReminderListView()
                .environmentObject(vm)
                .onAppear { vm.bootstrap() }
        }
    }
}
