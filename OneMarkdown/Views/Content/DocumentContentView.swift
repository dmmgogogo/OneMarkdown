import SwiftUI

/// 内容区：WebView 常驻（保证 index.html 提前加载），无文档时叠加空状态。
struct DocumentContentView: View {
    @Environment(WorkspaceViewModel.self) private var vm

    var body: some View {
        ZStack(alignment: .top) {
            MarkdownWebView(bridge: vm.bridge)
                .opacity(vm.hasDocument ? 1 : 0)

            if !vm.hasDocument {
                EmptyStateView()
            }

            VStack(spacing: 0) {
                if let banner = vm.banner {
                    BannerView(banner: banner) { vm.dismissBanner() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if vm.isFindVisible {
                    HStack {
                        Spacer()
                        FindBarView()
                            .padding(.top, 8)
                            .padding(.trailing, 16)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: vm.banner)
        .animation(.easeInOut(duration: 0.18), value: vm.isFindVisible)
    }
}
