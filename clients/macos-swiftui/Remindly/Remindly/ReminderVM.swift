import Foundation
import AVFoundation
import Combine

@MainActor
class ReminderVM: ObservableObject {
    @Published var occurrences: [OccurrenceResponse] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
    
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    private let apiClient = APIClient.shared
    
    func bootstrap() {
        Task {
            do {
                // Auto-authenticate in dev mode
                _ = try await apiClient.authenticate(email: "senior@example.com")
                isAuthenticated = true
                await refresh()
            } catch {
                errorMessage = "Failed to authenticate: \(error.localizedDescription)"
            }
        }
    }
    
    func refresh() async {
        isLoading = true
        errorMessage = nil
        
        do {
            occurrences = try await apiClient.fetchTodayReminders()
        } catch {
            errorMessage = "Failed to load reminders: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func acknowledge(occurrence: OccurrenceResponse, kind: String) async {
        do {
            try await apiClient.acknowledge(occurrenceId: occurrence.id, kind: kind)
            await refresh()
        } catch {
            errorMessage = "Failed to acknowledge: \(error.localizedDescription)"
        }
    }
    
    nonisolated func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.4 // Slower for seniors
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }
}
