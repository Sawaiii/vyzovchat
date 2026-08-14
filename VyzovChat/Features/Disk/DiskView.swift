import SwiftUI

/// Общий диск мероприятий. Папки открываются настоящим push-переходом,
/// поэтому работает нативный свайп-назад с анимацией.
struct DiskView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics

    /// Диск = папки мероприятий + фотобанк (теговая библиотека) — это одно и то же
    /// хранилище, поэтому фотобанк живёт здесь отдельным режимом, а не вкладкой.
    enum Mode: Hashable { case folders, photobank }
    @State private var mode: Mode = .folders

    @State private var stack: [String] = []          // пути открытых папок

    private var modePicker: some View {
        Picker("", selection: $mode.animation(.easeInOut(duration: 0.25))) {
            Text("Папки").tag(Mode.folders)
            Text("Фотобанк").tag(Mode.photobank)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    var body: some View {
        NavigationStack(path: $stack) {
            // Свайп между «Папки» и «Фотобанк» — как пейджер тем в чатах.
            TabView(selection: $mode) {
                foldersPage.tag(Mode.folders)
                PhotobankBrowser().tag(Mode.photobank)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            // Внутри стека: полоса уезжает вместе с экраном при переходе в папку.
            .appTabBar()
            .toolbar { ToolbarItem(placement: .principal) { modePicker } }
            .navigationDestination(for: String.self) { path in
                DiskFolderView(path: path)
                    .environmentObject(session)
            }
        }
    }

    /// Страница «Папки»: браузер папок на общем фоне.
    /// Поиска по папкам на сервере нет — раньше он ходил в эндпоинт, которого
    /// в новом API не существует.
    private var foldersPage: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()
            DiskFolderView(path: "")
        }
    }
}

/// Содержимое одной папки диска.
struct DiskFolderView: View {
    let path: String

    @EnvironmentObject private var session: AppSession
    @Environment(\.adaptiveMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    @State private var entries: [DiskEntryDTO] = []
    @State private var isLoading = true
    @State private var mediaPreview: MediaPreview?

    // Выделение и операции
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var errorText: String?

    /// Удаление на Диске доступно админу и реализатору (у него там полный доступ).
    private var isAdmin: Bool {
        guard let user = session.currentUser else { return false }
        return user.isAdmin || user.isImplementer
    }

    private var folders: [DiskEntryDTO] { entries.filter(\.isDir) }
    private var media: [DiskEntryDTO] { entries.filter { !$0.isDir && $0.isMedia } }
    private var files: [DiskEntryDTO] { entries.filter { !$0.isDir && !$0.isMedia } }

    private let grid = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        ZStack {
            AmbientBackground()
            if isLoading {
                ProgressView().tint(Theme.accent)
            } else if entries.isEmpty {
                EmptyState(icon: "folder", title: "Пусто",
                           message: "Здесь появятся папки мероприятий с выгруженными фото.")
            } else {
                VStack(spacing: 0) {
                    content
                    if selecting { actionBar }
                }
            }
        }
        .navigationTitle(path.isEmpty ? "Диск" : (path.split(separator: "/").last.map(String.init) ?? "Папка"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // На корне (список папок мероприятий) выбор не нужен — целиком папку
            // никто не выгружает. Кнопка «Выбрать» только внутри папок.
            if !path.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Готово" : "Выбрать") {
                        withAnimation(.smooth(duration: 0.2)) {
                            selecting.toggle()
                            if !selecting { selected.removeAll() }
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onReceive(RealtimeService.shared.diskChanged) { _ in Task { await load() } }
        .fullScreenCover(item: $mediaPreview) { p in
            MediaPager(items: p.items, startIndex: p.index)
        }
        .confirmationDialog("Удалить выбранное?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить (\(selected.count))", role: .destructive) { Task { await deleteSelected() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Файлы удалятся из хранилища безвозвратно.")
        }
    }

    /// Панель действий над выбранным. Удаление — единственная операция, которую
    /// поддерживает сервер: перемещения и сборки архива в новом API нет.
    private var actionBar: some View {
        VStack(spacing: Spacing.xs) {
            if let errorText { ErrorBanner(text: errorText) }
            if isAdmin {
                Button { confirmDelete = true } label: {
                    actionLabel("Удалить", "trash", color: Theme.danger)
                }
                .disabled(selected.isEmpty || busy)
            }
            Text("Выбрано: \(selected.count)")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.s)
        .background(Theme.panel)
    }

    private func actionLabel(_ title: String, _ icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
            Text(title).font(.system(size: 10))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
    }

    private func toggleSelect(_ p: String) {
        if selected.contains(p) { selected.remove(p) } else { selected.insert(p) }
        Haptics.selection()
    }

    private func deleteSelected() async {
        busy = true; errorText = nil
        do {
            try await session.disk.delete(keys: Array(selected))
            selected.removeAll()
            await load()
        } catch { errorText = error.localizedDescription }
        busy = false
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if !folders.isEmpty {
                    VStack(spacing: Spacing.xs) {
                        ForEach(folders) { entry in
                            if selecting {
                                Button { toggleSelect(entry.path) } label: { folderRow(entry) }
                                    .buttonStyle(PressableStyle())
                            } else {
                                NavigationLink(value: entry.path) { folderRow(entry) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }

                if !media.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Фото и видео").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                        LazyVGrid(columns: grid, spacing: 6) {
                            ForEach(media) { entry in mediaCell(entry) }
                        }
                    }
                }

                if !files.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Файлы").font(Typography.headline).foregroundStyle(Theme.textPrimary)
                        VStack(spacing: Spacing.xs) {
                            ForEach(files) { entry in fileRow(entry) }
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, Spacing.s)
        }
    }

    private func folderRow(_ entry: DiskEntryDTO) -> some View {
        HStack(spacing: Spacing.s) {
            if selecting {
                Image(systemName: selected.contains(entry.path) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(entry.path) ? Theme.accent : Theme.textSecondary)
            }
            Image(systemName: "folder.fill").font(.title3).foregroundStyle(Theme.groupTitle)
            // Сколько внутри — сервер по папке не считает, поэтому только название.
            Text(entry.name).font(Typography.callout.weight(.medium))
                .foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(Spacing.s)
        .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        .contentShape(Rectangle())
    }

    private func mediaCell(_ entry: DiskEntryDTO) -> some View {
        Button {
            if selecting { toggleSelect(entry.path) } else { openMedia(entry) }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    CachedAsyncImage(url: entry.fileURL) {
                        $0.resizable().scaledToFill()
                    } placeholder: {
                        Theme.panel2
                    }
                )
                .overlay {
                    if entry.isVideo {
                        Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: selected.contains(entry.path) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(entry.path) ? Theme.accent : .white.opacity(0.9))
                            .background(Circle().fill(.black.opacity(0.25)))
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ entry: DiskEntryDTO) -> some View {
        Button {
            if selecting { toggleSelect(entry.path) }
            else if let url = entry.downloadFileURL { openURL(url) }
        } label: {
            HStack(spacing: Spacing.s) {
                if selecting {
                    Image(systemName: selected.contains(entry.path) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(entry.path) ? Theme.accent : Theme.textSecondary)
                }
                Image(systemName: "doc.fill").foregroundStyle(Theme.accent)
                Text(entry.name).font(Typography.callout).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                if let size = entry.size {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Spacing.s)
            .glass(cornerRadius: Theme.cornerSmall, elevated: false)
        }
        .buttonStyle(.plain)
    }

    private func openMedia(_ entry: DiskEntryDTO) {
        let items = media.map { e in
            Message.Attachment(id: e.path,
                               remoteURL: e.fileURL,
                               fileName: e.name, sizeBytes: e.size,
                               isVideo: e.isVideo, isFile: false)
        }
        let idx = media.firstIndex { $0.path == entry.path } ?? 0
        mediaPreview = MediaPreview(items: items, index: idx)
    }

    private func load() async {
        let result = await session.disk.list(path: path)
        entries = result?.entries ?? []
        isLoading = false
    }
}
