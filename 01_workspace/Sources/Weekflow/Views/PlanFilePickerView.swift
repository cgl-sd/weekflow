import SwiftUI
import UniformTypeIdentifiers

/// Custom in-app file picker presented as a SwiftUI sheet.
/// Replaces NSOpenPanel/NSSavePanel to guarantee the menu bar never changes
/// (system panels hijack the menu bar even when presented as sheets).
struct PlanFilePickerView: View {
    enum Mode: Identifiable {
        case importFile
        case exportFile(defaultName: String)

        var id: String {
            switch self {
            case .importFile: return "import"
            case .exportFile(let name): return "export-\(name)"
            }
        }
    }

    let mode: Mode
    let onConfirm: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentDirectory: URL
    @State private var directories: [URL] = []
    @State private var jsonFiles: [URL] = []
    @State private var selectedFile: URL?
    @State private var fileName: String
    @State private var navigateUp: URL?

    init(mode: Mode, onConfirm: @escaping (URL) -> Void) {
        self.mode = mode
        self.onConfirm = onConfirm
        let home = FileManager.default.homeDirectoryForCurrentUser
        _currentDirectory = State(initialValue: home)
        switch mode {
        case .importFile:
            _fileName = State(initialValue: "")
        case .exportFile(let defaultName):
            _fileName = State(initialValue: defaultName)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pathBar
            Divider()
            fileList
            Divider()
            footer
        }
        .frame(width: 520, height: 400)
        .onAppear { loadDirectory(currentDirectory) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            WeekflowButton { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(WeekflowPalette.surfaceHover, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var title: String {
        switch mode {
        case .importFile: return "导入周规划"
        case .exportFile: return "导出周规划"
        }
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        HStack(spacing: 6) {
            WeekflowButton {
                if let parent = navigateUp {
                    loadDirectory(parent)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(navigateUp != nil ? WeekflowPalette.textSecondary : WeekflowPalette.textMuted)
                    .frame(width: 26, height: 22)
                    .background(WeekflowPalette.surface, in: RoundedRectangle(cornerRadius: 5))
            }
            .disabled(navigateUp == nil)

            WeekflowButton {
                loadDirectory(FileManager.default.homeDirectoryForCurrentUser)
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .frame(width: 26, height: 22)
                    .background(WeekflowPalette.surface, in: RoundedRectangle(cornerRadius: 5))
            }

            WeekflowButton {
                loadDirectory(URL(fileURLWithPath: "/Users/Shared"))
            } label: {
                Image(systemName: "person.2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .frame(width: 26, height: 22)
                    .background(WeekflowPalette.surface, in: RoundedRectangle(cornerRadius: 5))
            }

            Spacer()

            Text(currentDirectory.lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(WeekflowPalette.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(directories, id: \.self) { dir in
                    directoryRow(dir)
                }
                if isImportMode {
                    ForEach(jsonFiles, id: \.self) { file in
                        fileRow(file)
                    }
                }
                if directories.isEmpty && (isImportMode && jsonFiles.isEmpty) {
                    Text("此文件夹为空")
                        .font(.system(size: 12))
                        .foregroundStyle(WeekflowPalette.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var isImportMode: Bool {
        if case .importFile = mode { return true }
        return false
    }

    private func directoryRow(_ dir: URL) -> some View {
        WeekflowButton {
            loadDirectory(dir)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.blue.opacity(0.7))
                Text(dir.lastPathComponent)
                    .font(.system(size: 13))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func fileRow(_ file: URL) -> some View {
        let isSelected = selectedFile == file
        return WeekflowButton {
            selectedFile = file
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange.opacity(0.8))
                Text(file.lastPathComponent)
                    .font(.system(size: 13))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? WeekflowPalette.surfaceSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if case .exportFile = mode {
                HStack(spacing: 6) {
                    Text("文件名:")
                        .font(.system(size: 12))
                        .foregroundStyle(WeekflowPalette.textSecondary)
                    TextField("文件名", text: $fileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .font(.system(size: 12))
                }
            }
            Spacer()
            WeekflowButton { dismiss() } label: {
                Text("取消")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(WeekflowPalette.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(WeekflowPalette.borderDefault, lineWidth: 1))
            }
            WeekflowButton { confirm() } label: {
                Text(confirmLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(canConfirm ? WeekflowPalette.objective : WeekflowPalette.objective.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            }
            .disabled(!canConfirm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var confirmLabel: String {
        switch mode {
        case .importFile: return "导入"
        case .exportFile: return "导出"
        }
    }

    private var canConfirm: Bool {
        switch mode {
        case .importFile:
            return selectedFile != nil
        case .exportFile:
            return !fileName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // MARK: - Actions

    private func loadDirectory(_ url: URL) {
        currentDirectory = url
        selectedFile = nil
        navigateUp = url.path != "/" ? url.deletingLastPathComponent() : nil

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            directories = []
            jsonFiles = []
            return
        }

        directories = contents.filter { item in
            (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        jsonFiles = contents.filter { item in
            (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false
                && item.pathExtension.lowercased() == "json"
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func confirm() {
        switch mode {
        case .importFile:
            guard let file = selectedFile else { return }
            dismiss()
            onConfirm(file)
        case .exportFile:
            var name = fileName.trimmingCharacters(in: .whitespaces)
            if !name.hasSuffix(".json") { name += ".json" }
            let url = currentDirectory.appendingPathComponent(name)
            dismiss()
            onConfirm(url)
        }
    }
}
