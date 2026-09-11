import SwiftUI

struct MainWindowView: View {
    @Environment(WorkspaceViewModel.self) private var vm
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var appState: AppState { AppState.shared }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)
        } detail: {
            DocumentContentView()
        }
        .navigationTitle(vm.documentTitle)
        .navigationSubtitle(vm.documentSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    vm.showOpenPanel()
                } label: {
                    Label("打开", systemImage: "folder")
                }
                .help("打开文件或文件夹 (⌘O)")

                Button {
                    vm.reload()
                } label: {
                    Label("重新加载", systemImage: "arrow.clockwise")
                }
                .help("重新加载 (⌘R)")
                .disabled(!vm.hasDocument)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            vm.openAll(urls)
            return true
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            columnVisibility = vm.isSidebarVisible ? .all : .detailOnly
            appState.openMainWindow = { openWindow(id: "main") }
            consumePendingURLs()
        }
        .onChange(of: appState.pendingOpenURLs) { _, _ in
            consumePendingURLs()
        }
        .onChange(of: vm.isSidebarVisible) { _, visible in
            let target: NavigationSplitViewVisibility = visible ? .all : .detailOnly
            if columnVisibility != target { columnVisibility = target }
        }
        .onChange(of: columnVisibility) { _, value in
            let visible = value != .detailOnly
            if vm.isSidebarVisible != visible { vm.isSidebarVisible = visible }
        }
    }

    private func consumePendingURLs() {
        let urls = appState.pendingOpenURLs
        guard !urls.isEmpty else { return }
        appState.pendingOpenURLs.removeAll()
        vm.openAll(urls)
    }
}
