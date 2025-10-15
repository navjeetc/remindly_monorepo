import Foundation
import Security
import Combine

/// Manages authentication state and secure JWT token storage in Keychain
@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    
    private let keychainService = "com.remindly.app"
    private let tokenKey = "jwt_token"
    private let emailKey = "user_email"
    
    private init() {
        // Check if we have a stored token on init
        if let token = loadToken() {
            // Check if token is expired
            if !isTokenExpired() {
                isAuthenticated = true
                userEmail = loadEmail()
                // Set token in API client
                APIClient.shared.setToken(token)
                
                // Start session monitoring
                startSessionMonitoring()
            } else {
                // Token expired, clear it
                logout()
            }
        }
    }
    
    private func startSessionMonitoring() {
        // Check token expiration every 5 minutes
        Task {
            while isAuthenticated {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
                await MainActor.run {
                    refreshAuthState()
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Request a magic link to be sent to the user's email
    func requestMagicLink(email: String) async throws {
        let baseURL = Config.baseURL
        guard let url = URL(string: "\(baseURL)/magic/request?email=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            throw AuthError.invalidEmail
        }
        
        let (_, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // Store email for later use
        saveEmail(email)
        
        print("✅ Magic link requested for \(email)")
    }
    
    /// Verify a magic link token and authenticate the user
    func verifyMagicLink(token: String) async throws {
        let baseURL = Config.baseURL
        
        // Build URL with URLComponents to avoid double-encoding
        var components = URLComponents(string: "\(baseURL)/magic/verify")!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        
        guard let url = components.url else {
            throw AuthError.invalidToken
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            throw AuthError.unauthorized
        }
        
        guard let jwt = String(data: data, encoding: .utf8), !jwt.isEmpty else {
            throw AuthError.invalidToken
        }
        
        // Save token securely
        try saveToken(jwt)
        
        // Set token in API client
        APIClient.shared.setToken(jwt)
        
        // Update authentication state
        isAuthenticated = true
        
        // Start session monitoring
        startSessionMonitoring()
        
        print("✅ Magic link verified, user authenticated")
    }
    
    /// Authenticate using dev mode (development only)
    func authenticateDev(email: String) async throws {
        guard Config.baseURL.contains("localhost") || Config.baseURL.contains("127.0.0.1") else {
            throw AuthError.devModeNotAvailable
        }
        
        let token = try await APIClient.shared.authenticate(email: email)
        
        // Save token and email
        try saveToken(token)
        saveEmail(email)
        
        // Update authentication state
        isAuthenticated = true
        userEmail = email
        
        // Start session monitoring
        startSessionMonitoring()
        
        print("✅ Dev mode authentication successful for \(email)")
    }
    
    /// Logout the user and clear stored credentials
    func logout() {
        deleteToken()
        deleteEmail()
        isAuthenticated = false
        userEmail = nil
        print("✅ User logged out")
    }
    
    /// Check if the JWT token is expired
    func isTokenExpired() -> Bool {
        guard let token = loadToken() else {
            return true
        }
        
        // Decode JWT to check expiration
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            return true
        }
        
        // Decode payload (second segment)
        var base64 = segments[1]
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }
        
        let expirationDate = Date(timeIntervalSince1970: exp)
        let isExpired = expirationDate < Date()
        
        if isExpired {
            print("⚠️ JWT token expired at \(expirationDate)")
        }
        
        return isExpired
    }
    
    /// Refresh the authentication state (check if token is still valid)
    func refreshAuthState() {
        if isTokenExpired() {
            logout()
        }
    }
    
    // MARK: - Keychain Operations
    
    private func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw AuthError.keychainError
        }
        
        // Delete existing token first
        deleteToken()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            print("❌ Keychain save error: \(status)")
            throw AuthError.keychainError
        }
        
        print("✅ JWT token saved to Keychain")
    }
    
    private func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    private func saveEmail(_ email: String) {
        UserDefaults.standard.set(email, forKey: emailKey)
    }
    
    private func loadEmail() -> String? {
        return UserDefaults.standard.string(forKey: emailKey)
    }
    
    private func deleteEmail() {
        UserDefaults.standard.removeObject(forKey: emailKey)
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidEmail
    case invalidToken
    case unauthorized
    case networkError
    case serverError(statusCode: Int)
    case keychainError
    case devModeNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Invalid email address"
        case .invalidToken:
            return "Invalid or expired token"
        case .unauthorized:
            return "Authentication failed"
        case .networkError:
            return "Network error occurred"
        case .serverError(let code):
            return "Server error (code: \(code))"
        case .keychainError:
            return "Failed to store credentials securely"
        case .devModeNotAvailable:
            return "Dev mode only available in development"
        }
    }
}
