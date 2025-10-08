import SwiftUI

struct EditReminderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var vm: ReminderVM
    let reminderId: Int
    
    private let dataManager = DataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    
    @State private var reminder: ReminderResponse?
    @State private var title = ""
    @State private var notes = ""
    @State private var category: ReminderCategory = .medication
    @State private var selectedTime = Date()
    @State private var recurrenceType: RecurrenceType = .daily
    @State private var customHours = 2
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            if isLoading {
                ProgressView("Loading...")
                    .frame(minWidth: 500, minHeight: 600)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Title Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Reminder Title")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            TextField("e.g., Take medication", text: $title)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.textBackgroundColor)))
                                )
                                .font(.system(size: 22))
                        }
                        
                        // Notes Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Notes (Optional)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            TextEditor(text: $notes)
                                .font(.system(size: 20))
                                .frame(height: 100)
                                .padding(4)
                                .border(Color.gray.opacity(0.3), width: 1)
                                .cornerRadius(4)
                        }
                        
                        // Category Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Category")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            
                            HStack(spacing: 12) {
                                ForEach(ReminderCategory.allCases, id: \.self) { cat in
                                    Button(action: {
                                        category = cat
                                        print("🔄 Category changed to: \(cat.rawValue)")
                                    }) {
                                        VStack(spacing: 4) {
                                            Text(cat.icon)
                                                .font(.system(size: 28))
                                            Text(cat.rawValue.capitalized)
                                                .font(.system(size: 16))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(category == cat ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(category == cat ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Time Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Time")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            HStack {
                                DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .font(.system(size: 20))
                                    .datePickerStyle(.stepperField)
                                Spacer()
                            }
                        }
                        
                        // Recurrence Section
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Repeat")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            
                            HStack {
                                Picker("Frequency", selection: $recurrenceType) {
                                    ForEach(RecurrenceType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .font(.system(size: 20))
                                Spacer()
                            }
                            
                            if recurrenceType == .everyNHours {
                                Stepper("Every \(customHours) hours", value: $customHours, in: 1...12)
                                    .font(.system(size: 20))
                                    .padding(.top, 8)
                            }
                        }
                        
                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.system(size: 16))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(24)
                }
                .frame(minWidth: 500, minHeight: 600)
                .navigationTitle("Edit Reminder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.system(size: 18))
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await saveReminder()
                            }
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .disabled(title.isEmpty || isSaving)
                    }
                }
                .disabled(isSaving)
            }
        }
        .task {
            await loadReminder()
        }
    }
    
    private func loadReminder() async {
        do {
            if networkMonitor.effectivelyConnected {
                // Online: fetch from API
                print("📡 Loading reminder from API...")
                let reminders = try await vm.apiClient.fetchReminders()
                if let found = reminders.first(where: { $0.id == reminderId }) {
                    reminder = found
                    title = found.title
                    notes = found.notes ?? ""
                    print("📋 Loaded category from API: '\(found.category)'")
                    category = ReminderCategory(rawValue: found.category) ?? .medication
                    print("📋 Parsed category: \(category.rawValue)")
                    parseRRule(found.rrule)
                    print("✅ Loaded reminder from API")
                } else {
                    errorMessage = "Reminder not found"
                }
            } else {
                // Offline: load from local cache
                print("📱 Loading reminder from cache (offline)...")
                let localReminders = try dataManager.fetchReminders()
                print("📱 Found \(localReminders.count) cached reminders")
                if let found = localReminders.first(where: { $0.id == reminderId }) {
                    title = found.title
                    notes = found.notes ?? ""
                    category = ReminderCategory(rawValue: found.category) ?? .medication
                    parseRRule(found.rrule)
                    print("✅ Loaded reminder from cache")
                } else {
                    errorMessage = "Reminder not found in cache. Please go online to load it."
                }
            }
            isLoading = false
        } catch {
            print("❌ Error loading reminder: \(error)")
            errorMessage = "Failed to load reminder: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func parseRRule(_ rrule: String) {
        // Parse recurrence type
        if rrule.contains("FREQ=DAILY") {
            recurrenceType = .daily
        } else if rrule.contains("FREQ=HOURLY") {
            recurrenceType = .everyNHours
            // Extract interval if present
            if let range = rrule.range(of: "INTERVAL=(\\d+)", options: .regularExpression) {
                let intervalStr = rrule[range].replacingOccurrences(of: "INTERVAL=", with: "")
                customHours = Int(intervalStr) ?? 2
            }
        } else if rrule.contains("BYDAY=MO,TU,WE,TH,FR") {
            recurrenceType = .weekdays
        } else if rrule.contains("BYDAY=SA,SU") {
            recurrenceType = .weekends
        }
        
        // Parse time from BYHOUR and BYMINUTE
        var hour = 9 // Default
        var minute = 0 // Default
        
        if let hourRange = rrule.range(of: "BYHOUR=(\\d+)", options: .regularExpression) {
            let hourStr = rrule[hourRange].replacingOccurrences(of: "BYHOUR=", with: "")
            hour = Int(hourStr) ?? 9
        }
        
        if let minuteRange = rrule.range(of: "BYMINUTE=(\\d+)", options: .regularExpression) {
            let minuteStr = rrule[minuteRange].replacingOccurrences(of: "BYMINUTE=", with: "")
            minute = Int(minuteStr) ?? 0
        }
        
        // Set the selectedTime to the parsed time
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        if let date = calendar.date(from: components) {
            selectedTime = date
            print("⏰ Parsed time from rrule: \(hour):\(minute) -> \(selectedTime)")
        }
    }
    
    private func saveReminder() async {
        guard !title.isEmpty else {
            errorMessage = "Title is required"
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        do {
            let rrule = generateRRule()
            print("💾 Saving reminder with category: '\(category.rawValue)'")
            try await vm.updateReminder(
                id: reminderId,
                title: title,
                notes: notes.isEmpty ? nil : notes,
                category: category.rawValue,
                rrule: rrule
            )
            // Small delay to ensure UI updates propagate before dismissing
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            dismiss()
        } catch {
            errorMessage = "Failed to update reminder: \(error.localizedDescription)"
            isSaving = false
        }
    }
    
    private func generateRRule() -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedTime)
        let minute = calendar.component(.minute, from: selectedTime)
        
        switch recurrenceType {
        case .daily:
            return "FREQ=DAILY;BYHOUR=\(hour);BYMINUTE=\(minute)"
        case .everyNHours:
            // For hourly intervals, just use FREQ and INTERVAL
            // The backend will use the schedule start time
            return "FREQ=HOURLY;INTERVAL=\(customHours)"
        case .weekdays:
            return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=\(hour);BYMINUTE=\(minute)"
        case .weekends:
            return "FREQ=WEEKLY;BYDAY=SA,SU;BYHOUR=\(hour);BYMINUTE=\(minute)"
        }
    }
}
