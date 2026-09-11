import SwiftUI

/// 文件树（无过滤时）/ 匹配文件的扁平列表（有过滤时）。
struct FileTreeView: View {
    @Environment(WorkspaceViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        Group {
            if vm.isBuildingTree {
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取目录…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let tree = vm.tree {
                if vm.filterText.isEmpty {
                    List(tree.children ?? [], children: \.children, selection: $vm.selectedNodeID) { node in
                        row(for: node)
                    }
                    .listStyle(.sidebar)
                } else {
                    let matches = vm.filteredFiles
                    if matches.isEmpty {
                        placeholder("没有匹配的文件")
                    } else {
                        List(matches, selection: $vm.selectedNodeID) { node in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(node.name, systemImage: "doc.text")
                                Text(vm.relativePath(of: node.url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .contextMenu { contextMenu(for: node) }
                        }
                        .listStyle(.sidebar)
                    }
                }
            } else if vm.rootFolder == nil {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("打开一个文件夹\n浏览其中的 Markdown")
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开文件夹…") { vm.showOpenFolderPanel() }
                        .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                placeholder("此文件夹中没有 Markdown 文件")
            }
        }
        .onChange(of: vm.selectedNodeID) { _, id in
            vm.select(nodeID: id)
        }
        .alert("重命名", isPresented: Binding(get: { vm.renameTarget != nil }, set: { if !$0 { vm.cancelRename() } })) {
            TextField("名称", text: $vm.renameText)
            Button("重命名") { vm.commitRename() }
                .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) { vm.cancelRename() }
        } message: {
            Text("输入新名称（含扩展名）")
        }
        .alert("移到废纸篓", isPresented: Binding(get: { vm.trashTarget != nil }, set: { if !$0 { vm.cancelTrash() } })) {
            Button("移到废纸篓", role: .destructive) { vm.commitTrash() }
            Button("取消", role: .cancel) { vm.cancelTrash() }
        } message: {
            Text("确定要把“\(vm.trashTarget?.lastPathComponent ?? "")”移到废纸篓吗？\n可以在废纸篓中找回。")
        }
    }

    @ViewBuilder
    private func row(for node: FileNode) -> some View {
        Label {
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
        }
        .help(node.url.path)
        .contextMenu { contextMenu(for: node) }
    }

    @ViewBuilder
    private func contextMenu(for node: FileNode) -> some View {
        Button("在 Finder 中显示") { vm.revealInFinder(node.url) }
        Button("拷贝路径") { vm.copyPath(node.url) }
        if node.isDirectory {
            Button("设为根目录") { vm.openFolder(node.url) }
        }
        Divider()
        Button("重命名…") { vm.beginRename(node.url) }
        Button("移到废纸篓") { vm.beginTrash(node.url) }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
