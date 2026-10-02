import SwiftData
import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Weekly Goal").font(.title2.bold())
            Text("Set the recurring target used by every Monday–Sunday week.")
                .foregroundStyle(.secondary)
            GoalForm(closeAfterSave: false)
            Divider()
            Text("Default Work Start").font(.headline)
            Text("Used for a new day when there is no earlier entry to continue from.")
                .foregroundStyle(.secondary)
            WorkStartForm()
        }
        .padding(24)
    }
}

struct GoalEditorView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Weekly Goal").font(.title2.bold())
            GoalForm(closeAfterSave: true)
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct GoalForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let closeAfterSave: Bool
    @State private var enabled = true
    @State private var hours = 40.0
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Enable weekly goal", isOn: $enabled)
            HStack {
                Text("Target")
                Spacer()
                TextField("Hours", value: $hours, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .disabled(!enabled)
                Stepper("hours", value: $hours, in: 0.25...168, step: 0.25)
                    .labelsHidden()
                    .disabled(!enabled)
                Text("hours")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                if closeAfterSave { Button("Cancel", role: .cancel) { dismiss() } }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        do {
            let value = try SwiftDataSettingsRepository(context: modelContext).current().weeklyGoalMinutes
            enabled = value != nil
            hours = Double(value ?? 2_400) / 60
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let rawMinutes = Int((hours * 60).rounded())
            let quarterHourMinutes = Int((Double(rawMinutes) / 15).rounded()) * 15
            try SwiftDataSettingsRepository(context: modelContext).setWeeklyGoal(minutes: enabled ? quarterHourMinutes : nil)
            errorMessage = nil
            if closeAfterSave { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WorkStartForm: View {
    @Environment(\.modelContext) private var modelContext

    @State private var startTime = Date.now
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DatePicker("Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                Spacer()
                Button("Save Start Time", action: save)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        do {
            let minutes = try SwiftDataSettingsRepository(context: modelContext).current().defaultWorkStartMinutes
            let calendar = Calendar.current
            startTime = calendar.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: Date.now
            ) ?? Date.now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        do {
            try SwiftDataSettingsRepository(context: modelContext).setDefaultWorkStart(minutes: minutes)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
