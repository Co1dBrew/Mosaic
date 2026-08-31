import SwiftUI
import UIKit

/// Create/rename a folder with name, color, and icon (PRD §4.1).
struct FolderEditSheet: View {
    struct Result {
        var name: String
        var colorHex: String
        var iconName: String
        var sortOrder: Int
    }

    let folder: Folder?
    let nextSortOrder: Int
    let onSave: (Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    @State private var iconName: String

    init(folder: Folder?, nextSortOrder: Int, onSave: @escaping (Result) -> Void) {
        self.folder = folder
        self.nextSortOrder = nextSortOrder
        self.onSave = onSave
        _name = State(initialValue: folder?.name ?? "")
        _colorHex = State(initialValue: folder?.colorHex ?? FolderPalette.colors[0])
        _iconName = State(initialValue: folder?.iconName ?? FolderPalette.icons[0])
    }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("文件夹名称", text: $name)
                        .accessibilityIdentifier("folder.name")
                }
                Section("颜色") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FolderPalette.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white).font(.headline)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("图标") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FolderPalette.icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(icon == iconName ? Color(hex: colorHex).opacity(0.2) : Color(.secondarySystemBackground))
                                .foregroundStyle(icon == iconName ? Color(hex: colorHex) : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .onTapGesture { iconName = icon }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(folder == nil ? "新建文件夹" : "编辑文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(Result(
                            name: trimmed.isEmpty ? "未命名文件夹" : trimmed,
                            colorHex: colorHex,
                            iconName: iconName,
                            sortOrder: folder?.sortOrder ?? nextSortOrder
                        ))
                        dismiss()
                    }
                    .accessibilityIdentifier("folder.save")
                }
            }
        }
    }
}
