import SwiftUI

/// 菜单栏命令。
struct AppCommands: Commands {
    let viewModel: WorkspaceViewModel

    var body: some Commands {
        // 文件
        CommandGroup(after: .newItem) {
            Button("打开…") { viewModel.showOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("打开文件夹…") { viewModel.showOpenFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            recentMenu
            Divider()
            Button("重新加载") { viewModel.reload() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!viewModel.hasDocument)
            Button("在 Finder 中显示") { viewModel.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!viewModel.hasDocument && viewModel.rootFolder == nil)
            Divider()
            Button("重命名…") { if let url = viewModel.fileOperationTarget { viewModel.beginRename(url) } }
                .disabled(viewModel.fileOperationTarget == nil)
            Button("移到废纸篓") { if let url = viewModel.fileOperationTarget { viewModel.beginTrash(url) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.fileOperationTarget == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("导出为 PDF…") { viewModel.exportPDF() }
                .disabled(!viewModel.hasDocument)
            Button("打印…") { viewModel.printDocument() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!viewModel.hasDocument)
        }

        // 编辑 › 查找（替换系统文本查找组，避免 ⌘F 冲突）
        CommandGroup(replacing: .textEditing) {
            Button("查找…") { viewModel.toggleFind() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!viewModel.hasDocument)
            Button("查找下一个") { viewModel.findNext() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!viewModel.isFindVisible)
            Button("查找上一个") { viewModel.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!viewModel.isFindVisible)
        }

        // 显示
        CommandGroup(after: .sidebar) {
            Button(viewModel.isSidebarVisible ? "隐藏侧栏" : "显示侧栏") {
                viewModel.isSidebarVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("文件列表") { viewModel.sidebarMode = .files; viewModel.isSidebarVisible = true }
                .keyboardShortcut("1", modifiers: .command)
            Button("大纲") { viewModel.sidebarMode = .outline; viewModel.isSidebarVisible = true }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Button("放大") { viewModel.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("缩小") { viewModel.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("实际大小") { viewModel.zoomReset() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }

    private var recentMenu: some View {
        Menu("最近打开") {
            let urls = viewModel.recents.urls
            if urls.isEmpty {
                Text("无最近项目")
            } else {
                ForEach(urls, id: \.self) { url in
                    Button(url.lastPathComponent) { viewModel.open(url, force: true) }
                        .disabled(!viewModel.recents.exists(url))
                }
                Divider()
                Button("清除菜单") { viewModel.recents.clear() }
            }
        }
    }
}
