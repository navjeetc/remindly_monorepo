import SwiftUI

struct CreateReminderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var vm: ReminderVM

    @State private var title = ""
    @State private var notes = ""
    @State private var category: ReminderCategory = .medication
    @State private var selectedTime = Date()
    @State private var recurrenceType: RecurrenceType = .daily
    @State private var customHours = 2
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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
            .navigationTitle("New Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 18))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createReminder()
                        }
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .disabled(title.isEmpty || isCreating)
                }
            }
            .disabled(isCreating)
        }
    }

    private func createReminder() async {
        guard !title.isEmpty else {
            errorMessage = "Title is required"
            return
        }

        isCreating = true
        errorMessage = nil

        do {
            let rrule = generateRRule()
            try await vm.createReminder(
                title: title,
                notes: notes.isEmpty ? nil : notes,
                category: category.rawValue,
                rrule: rrule,
                time: selectedTime
            )
            isCreating = false
            dismiss()
        } catch {
            errorMessage = "Failed to create reminder: \(error.localizedDescription)"
            isCreating = false
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
            return "FREQ=HOURLY;INTERVAL=\(customHours)"
        case .weekdays:
            return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=\(hour);BYMINUTE=\(minute)"
        case .weekends:
            return "FREQ=WEEKLY;BYDAY=SA,SU;BYHOUR=\(hour);BYMINUTE=\(minute)"
        }
    }
}

// MARK: - Supporting Types

enum ReminderCategory: String, CaseIterable {
    case medication
    case hydration
    case routine

    var icon: String {
        switch self {
        case .medication: return "💊"
        case .hydration: return "💧"
        case .routine: return "📋"
        }
    }
}

enum RecurrenceType: String, CaseIterable {
    case daily
    case everyNHours
    case weekdays
    case weekends

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .everyNHours: return "Every N Hours"
        case .weekdays: return "Weekdays (Mon-Fri)"
        case .weekends: return "Weekends (Sat-Sun)"
        }
    }
}

// MARK: - Preview

#Preview {
    CreateReminderView(vm: ReminderVM())
}
