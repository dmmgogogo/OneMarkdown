import SwiftUI

/// 文件树：按层懒加载（展开某个文件夹时才读取它的内容）；搜索时显示匹配文件的扁平列表。
struct FileTreeView: View {
    @Environment(WorkspaceViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        Group {
            if vm.rootFolder == nil {
                emptyRoot
            } else if !vm.filterText.isEmpty {
                searchList
            } else if let children = vm.rootChildren {
                if children.isEmpty {
                    placeholder("此文件夹中没有 Markdown 文件")
                } else {
                    List(selection: $vm.selectedNodeID) {
                        ForEach(children) { node in
                            FileNodeRow(node: node)
                        }
                    }
                    .listStyle(.sidebar)
                }
            } else {
                loading("正在读取目录…")
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

    // MARK: - 搜索结果

    private var searchList: some View {
        @Bindable var vm = vm
        return Group {
            if vm.isSearching {
                loading("正在扫描目录…")
            } else if vm.searchResults.isEmpty {
                placeholder("没有匹配的文件")
            } else {
                List(vm.searchResults, selection: $vm.selectedNodeID) { node in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(node.name, systemImage: "doc.text")
                        Text(vm.relativePath(of: node.url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contextMenu { FileNodeContextMenu(node: node) }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - 占位

    private var emptyRoot: some View {
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
    }

    private func loading(_ text: String) -> some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

/// 一行节点：文件是普通行；目录是 DisclosureGroup，展开时才向 ViewModel 请求读取内容。
private struct FileNodeRow: View {
    @Environment(WorkspaceViewModel.self) private var vm
    let node: FileNode

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { vm.isExpanded(node.url) },
                    set: { vm.setExpanded(node.url, $0) }
                )
            ) {
                if let children = vm.children(of: node.url) {
                    if children.isEmpty {
                        Text("没有 Markdown 文件")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(children) { child in
                            FileNodeRow(node: child)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("读取中…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } label: {
                label
            }
            .tag(node.url)
        } else {
            label
                .tag(node.url)
        }
    }

    private var label: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
        }
        .help(node.url.path)
        .contextMenu { FileNodeContextMenu(node: node) }
    }
}

/// 文件 / 目录的右键菜单。
private struct FileNodeContextMenu: View {
    @Environment(WorkspaceViewModel.self) private var vm
    let node: FileNode

    var body: some View {
        Button("在 Finder 中显示") { vm.revealInFinder(node.url) }
        Button("拷贝路径") { vm.copyPath(node.url) }
        if node.isDirectory {
            Button("设为根目录") { vm.openFolder(node.url) }
        }
        Divider()
        Button("重命名…") { vm.beginRename(node.url) }
        Button("移到废纸篓") { vm.beginTrash(node.url) }
    }
}
