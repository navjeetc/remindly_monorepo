import SwiftUI

@main
struct RemindlyApp: App {
    @StateObject private var vm = ReminderVM()
    
    var body: some Scene {
        WindowGroup {
            ReminderListView()
                .environmentObject(vm)
                .onAppear { vm.bootstrap() }
        }
    }
}
