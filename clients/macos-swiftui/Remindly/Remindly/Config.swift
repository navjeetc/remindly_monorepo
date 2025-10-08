import Foundation

struct Config {
    static let baseURL: String = {
        // Check for environment variable first (useful for different build configurations)
        if let envURL = ProcessInfo.processInfo.environment["API_BASE_URL"] {
            return envURL
        }
        
        // Default to localhost for development
        #if DEBUG
        return "http://localhost:5000"
        #else
        // Production URL - update this when deploying
        return "https://api.remindly.anakhsoft.com"
        #endif
    }()
}
