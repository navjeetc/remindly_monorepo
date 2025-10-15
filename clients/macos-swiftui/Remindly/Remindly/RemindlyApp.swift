import SwiftUI

@main
struct RemindlyApp: App {
    @StateObject private var vm = ReminderVM()
    @StateObject private var authManager = AuthenticationManager.shared
    
    init() {
        // Setup notification categories on app launch
        NotificationManager.shared.setupNotificationCategories()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ReminderListView()
                        .environmentObject(vm)
                        .onAppear { vm.bootstrap() }
                } else {
                    LoginView()
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Remindly") {
                    // Handle about action
                }
            }
            
            CommandGroup(after: .appSettings) {
                if authManager.isAuthenticated {
                    Button("Logout") {
                        authManager.logout()
                    }
                    .keyboardShortcut("L", modifiers: [.command, .shift])
                }
            }
        }
    }
    
    // MARK: - Deep Link Handling
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 Deep link received: \(url)")
        
        // Handle magic link verification
        // Expected format: remindly://magic/verify?token=<token>
        guard url.scheme == "remindly",
              url.host == "magic",
              url.path == "/verify" else {
            print("⚠️ Invalid deep link format")
            return
        }
        
        // Extract token from query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let token = queryItems.first(where: { $0.name == "token" })?.value else {
            print("⚠️ No token found in deep link")
            return
        }
        
        // Verify the magic link token
        Task {
            do {
                try await authManager.verifyMagicLink(token: token)
                print("✅ Magic link verified successfully")
            } catch {
                print("❌ Magic link verification failed: \(error.localizedDescription)")
            }
        }
    }
}
