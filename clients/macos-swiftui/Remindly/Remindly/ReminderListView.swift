import SwiftUI
import UserNotifications

struct ReminderListView: View {
    @EnvironmentObject var vm: ReminderVM
    @State private var showDebugInfo = false
    @State private var showCreateReminder = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Today's Reminders")
                    .font(.system(size: 36, weight: .bold))
                
                // Offline indicator
                if vm.isOffline {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                        Text("Offline")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                // Add reminder button
                Button(action: {
                    showCreateReminder = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Create new reminder")
                
                // Offline toggle (debug)
                Button(action: {
                    NetworkMonitor.shared.forceOffline.toggle()
                }) {
                    Image(systemName: NetworkMonitor.shared.forceOffline ? "network.slash" : "network")
                        .font(.system(size: 20))
                        .foregroundColor(NetworkMonitor.shared.forceOffline ? .red : .primary)
                }
                .buttonStyle(.plain)
                .help("Toggle offline mode (debug)")
                
                // Debug button
                Button(action: {
                    showDebugInfo.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .help("Show notification debug info")
                
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
            
            // Debug info
            if showDebugInfo {
                DebugNotificationView()
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
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
        .sheet(isPresented: $showCreateReminder) {
            CreateReminderView(vm: vm)
        }
    }
}

struct ReminderCard: View {
    @EnvironmentObject var vm: ReminderVM
    let occurrence: OccurrenceResponse
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    
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
        .contextMenu {
            Button(action: {
                showEditSheet = true
            }) {
                Label("Edit Reminder", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: {
                showDeleteAlert = true
            }) {
                Label("Delete Reminder", systemImage: "trash")
            }
        }
        .alert("Delete Reminder?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await vm.deleteReminder(id: occurrence.reminderId)
                }
            }
        } message: {
            Text("This will delete '\(occurrence.reminder.title)' and all its future occurrences.")
        }
        .sheet(isPresented: $showEditSheet) {
            EditReminderView(vm: vm, reminderId: occurrence.reminderId)
        }
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

struct DebugNotificationView: View {
    @State private var pendingCount = 0
    @State private var notifications: [String] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔔 Notification Debug")
                .font(.system(size: 18, weight: .bold))
            
            Text("Pending notifications: \(pendingCount)")
                .font(.system(size: 14))
            
            if !notifications.isEmpty {
                Divider()
                ForEach(notifications, id: \.self) { notification in
                    Text(notification)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Refresh") {
                Task {
                    await loadNotifications()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadNotifications()
        }
    }
    
    private func loadNotifications() async {
        let pending = await NotificationManager.shared.getPendingNotifications()
        pendingCount = pending.count
        notifications = pending.map { request in
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            let date = trigger?.nextTriggerDate()
            let dateStr = date?.formatted(date: .omitted, time: .shortened) ?? "Unknown"
            return "\(request.identifier): \(dateStr)"
        }
    }
}
