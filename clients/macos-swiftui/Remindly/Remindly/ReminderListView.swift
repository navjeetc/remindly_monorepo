import SwiftUI

struct ReminderListView: View {
    @EnvironmentObject var vm: ReminderVM
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Today's Reminders")
                    .font(.system(size: 36, weight: .bold))
                Spacer()
                Button(action: {
                    Task { await vm.refresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
            }
            .padding()
            
            // Error message
            if let error = vm.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
            
            // Loading indicator
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(2)
                    .padding()
            }
            
            // Reminders list
            ScrollView {
                VStack(spacing: 16) {
                    if vm.occurrences.isEmpty && !vm.isLoading {
                        Text("No reminders for today")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(vm.occurrences) { occurrence in
                            ReminderCard(occurrence: occurrence)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}

struct ReminderCard: View {
    @EnvironmentObject var vm: ReminderVM
    let occurrence: OccurrenceResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title and time
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(occurrence.reminder.title)
                        .font(.system(size: 28, weight: .semibold))
                    
                    Text(occurrence.scheduledAt, style: .time)
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                    
                    if let category = occurrence.reminder.category {
                        Text(category.capitalized)
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(categoryColor(category))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                // Speak button
                Button(action: {
                    vm.speak(occurrence.reminder.title)
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)
            }
            
            // Notes
            if let notes = occurrence.reminder.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            
            // Action buttons
            if occurrence.status == "pending" {
                HStack(spacing: 16) {
                    BigButton(title: "✓ Taken", color: .green) {
                        Task {
                            await vm.acknowledge(occurrence: occurrence, kind: "taken")
                        }
                    }
                    
                    BigButton(title: "⏰ Snooze", color: .orange) {
                        Task {
                            await vm.acknowledge(occurrence: occurrence, kind: "snooze")
                        }
                    }
                    
                    BigButton(title: "✗ Skip", color: .gray) {
                        Task {
                            await vm.acknowledge(occurrence: occurrence, kind: "skip")
                        }
                    }
                }
            } else {
                Text("Acknowledged")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.green)
            }
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "medication": return .blue
        case "hydration": return .cyan
        case "routine": return .purple
        default: return .gray
        }
    }
}

struct BigButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(color)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
