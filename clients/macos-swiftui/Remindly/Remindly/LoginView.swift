import SwiftUI

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    @State private var isDevelopmentMode = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App Logo/Title
            VStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Remindly")
                    .font(.system(size: 48, weight: .bold))
                
                Text("Your Personal Reminder Assistant")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
            
            // Login Form
            VStack(spacing: 20) {
                if showSuccessMessage {
                    successView
                } else {
                    loginForm
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
            
            // Development Mode Toggle (only in debug builds)
            #if DEBUG
            developmentModeToggle
            #endif
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            // Pre-fill email if we have it stored
            if let storedEmail = authManager.userEmail {
                email = storedEmail
            }
            
            // Check if we're in development mode
            isDevelopmentMode = Config.baseURL.contains("localhost") || Config.baseURL.contains("127.0.0.1")
        }
    }
    
    private var loginForm: some View {
        VStack(spacing: 20) {
            // Email Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Address")
                    .font(.system(size: 16, weight: .medium))
                
                TextField("your.email@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18))
                    .disabled(isLoading)
            }
            
            // Error Message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Login Button
            Button(action: handleLogin) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    }
                    Text(isLoading ? "Sending..." : "Send Magic Link")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || isLoading)
            
            // Development Mode Quick Login
            #if DEBUG
            if isDevelopmentMode {
                Button(action: handleDevLogin) {
                    Text("Quick Login (Dev Mode)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(email.isEmpty || isLoading)
            }
            #endif
        }
    }
    
    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Check Your Email")
                .font(.system(size: 28, weight: .bold))
            
            Text("We've sent a magic link to:")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Text(email)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.blue)
            
            Text("Click the link in your email to sign in.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            
            Button("Try Different Email") {
                showSuccessMessage = false
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .padding(.top, 20)
        }
    }
    
    #if DEBUG
    private var developmentModeToggle: some View {
        HStack {
            Image(systemName: isDevelopmentMode ? "hammer.fill" : "hammer")
                .foregroundColor(isDevelopmentMode ? .orange : .gray)
            Text("Development Mode")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    #endif
    
    // MARK: - Actions
    
    private func handleLogin() {
        guard !email.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.requestMagicLink(email: email)
                showSuccessMessage = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func handleDevLogin() {
        guard !email.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.authenticateDev(email: email)
                // Authentication state will be updated automatically
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
}
