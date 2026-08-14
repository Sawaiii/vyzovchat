import SwiftUI

/// Редактор тегов одного фото (только глобальный админ): добавить/убрать теги.
/// ИИ-теги и ручные показываем вместе; ручные помечаем точкой.
struct PhotobankTagEditor: View {
    let item: PhotobankItemDTO
    @ObservedObject var vm: PhotobankViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tags: [PhotobankTagDTO]
    @State private var newTag = ""
    @State private var suggestions: [String] = []
    @State private var busy = false

    init(item: PhotobankItemDTO, vm: PhotobankViewModel) {
        self.item = item
        self.vm = vm
        _tags = State(initialValue: item.tagList)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        preview

                        Text("Теги").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                        if tags.isEmpty {
                            Text("Тегов пока нет").font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(tags, id: \.tag) { t in tagChip(t) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        addField
                    }
                    .padding(Spacing.m)
                }
            }
            .navigationTitle("Теги фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }.disabled(busy)
                }
            }
            .task { suggestions = await vm.taxonomySuggestions() }
        }
    }

    private var preview: some View {
        Color.clear
            .frame(height: 180)
            .overlay(
                CachedAsyncImage(url: item.imageURL) { $0.resizable().scaledToFit() }
                    placeholder: { Theme.panel2 }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tagChip(_ t: PhotobankTagDTO) -> some View {
        HStack(spacing: 5) {
            if t.source == "admin" {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
            }
            Text(t.tag).font(.footnote)
            Button {
                Task { await remove(t.tag) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .disabled(busy)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glass(cornerRadius: 14, elevated: false)
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                TextField("Добавить тег…", text: $newTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await add(newTag) } }
                    .padding(.horizontal, Spacing.s).padding(.vertical, 10)
                    .glass(cornerRadius: Theme.cornerSmall, elevated: false)
                Button { Task { await add(newTag) } } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.textOnAccent)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                }
                .disabled(busy || newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !matchingSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matchingSuggestions, id: \.self) { s in
                            Button { Task { await add(s) } } label: {
                                Text(s).font(.footnote).foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.panel2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .horizontalStrip()
            }
        }
    }

    private var matchingSuggestions: [String] {
        let q = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        let existing = Set(tags.map { $0.tag.lowercased() })
        return suggestions
            .filter { !existing.contains($0.lowercased()) && (q.isEmpty || $0.lowercased().contains(q)) }
            .prefix(10).map { $0 }
    }

    private func add(_ tag: String) async {
        let t = tag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(where: { $0.tag.caseInsensitiveCompare(t) == .orderedSame }) else {
            newTag = ""; return
        }
        busy = true
        tags.append(PhotobankTagDTO(tag: t, source: "admin"))
        tags.sort { $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
        newTag = ""
        await vm.addTag(t, to: item)
        busy = false
    }

    private func remove(_ tag: String) async {
        busy = true
        tags.removeAll { $0.tag == tag }
        await vm.removeTag(tag, from: item)
        busy = false
    }
}
