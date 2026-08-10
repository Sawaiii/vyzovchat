import SwiftUI

/// Правка времени смены задним числом — право руководства.
///
/// Нужна, когда человек забыл отметиться или отметился не вовремя: часы в отчёте
/// должны сойтись с тем, что было на площадке. Сервер запоминает, кто и что
/// правил, и пишет об этом строкой в «Общий» — правка не прячется.
struct ShiftTimesEditor: View {
    let shift: CheckinDTO
    /// nil-поле сервер не трогает, поэтому шлём только то, что реально меняли.
    let onSave: (_ started: Date?, _ finished: Date?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editStart = false
    @State private var editFinish = false
    @State private var started = Date()
    @State private var finished = Date()
    @State private var busy = false

    private var canSave: Bool {
        guard !busy, editStart || editFinish else { return false }
        // Обе даты меняем — проверяем порядок сразу, не гоняя запрос ради 400.
        if editStart && editFinish { return finished >= started }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Text(shift.fio).font(Typography.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(currentText).font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Toggle("Изменить начало", isOn: $editStart).tint(Theme.accent)
                                if editStart {
                                    DatePicker("", selection: $started)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                                Divider().overlay(Theme.textSecondary.opacity(0.2))
                                Toggle("Изменить окончание", isOn: $editFinish).tint(Theme.accent)
                                if editFinish {
                                    DatePicker("", selection: $finished)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                            }
                        }

                        if editStart && editFinish && finished < started {
                            ErrorBanner(text: "Окончание раньше начала — так смена не бывает.")
                        }

                        Text("Правку увидят все: в «Общий» уйдёт строка о том, что вы изменили время этой смены.")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(Spacing.m)
                }
            }
            .navigationTitle("Время смены")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        Task {
                            busy = true
                            await onSave(editStart ? started : nil, editFinish ? finished : nil)
                            busy = false
                            dismiss()
                        }
                    }
                    .disabled(!canSave).bold()
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var currentText: String {
        let start = Self.format(DateParse.iso(shift.checked_at))
        guard let end = shift.finished_at else { return "Сейчас: с \(start), смена открыта" }
        return "Сейчас: \(start) — \(Self.format(DateParse.iso(end)))"
    }

    private func prefill() {
        started = DateParse.iso(shift.checked_at) ?? Date()
        finished = DateParse.iso(shift.finished_at) ?? Date()
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: date)
    }
}
