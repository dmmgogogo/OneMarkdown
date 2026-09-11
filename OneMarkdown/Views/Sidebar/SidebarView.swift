import SwiftUI

/// 侧栏：顶部模式切换（文件 / 大纲）+ 搜索框，中间列表，底部工具条。
struct SidebarView: View {
    @Environment(WorkspaceViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            Picker("侧栏模式", selection: $vm.sidebarMode) {
                Text("文件").tag(WorkspaceViewModel.SidebarMode.files)
                Text("大纲").tag(WorkspaceViewModel.SidebarMode.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)

            if vm.sidebarMode == .files {
                searchField
                FileTreeView()
            } else {
                OutlineView()
            }

            Divider()
            bottomBar
        }
    }

    private var searchField: some View {
        @Bindable var vm = vm
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("搜索文件名", text: $vm.filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !vm.filterText.isEmpty {
                Button {
                    vm.filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            if let root = vm.rootFolder {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(root.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(root.path)
            } else {
                Text("未打开文件夹")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                Button("打开文件夹…") { vm.showOpenFolderPanel() }
                Button("刷新文件列表") { vm.refreshTree() }
                    .disabled(vm.rootFolder == nil)
                Button("在 Finder 中显示") { vm.revealInFinder(vm.rootFolder) }
                    .disabled(vm.rootFolder == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button {
                vm.isSidebarVisible = false
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("隐藏侧栏 (⌘⇧L)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
