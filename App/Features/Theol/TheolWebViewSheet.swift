import BuctModel
import SwiftUI
import WebKit

/// 应用内免登北化在线网页容器：
/// 使用非持久化 `WKWebsiteDataStore`，在加载目标页面前注入当前账号原生登录获取的 Cookie，
/// 既可免登直接提交作业/做测验，又不会在切号或退出登录后残留凭据。
struct TheolWebViewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let context: TheolWebLaunchContext

    @State private var estimatedProgress: Double = 0
    @State private var isLoading: Bool = true
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var pageTitle: String = ""
    @State private var webCommand: TheolWebCommand?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView(value: max(0.08, estimatedProgress))
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                }

                TheolAuthenticatedWebView(
                    context: context,
                    estimatedProgress: $estimatedProgress,
                    isLoading: $isLoading,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    pageTitle: $pageTitle,
                    command: $webCommand
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle(pageTitle.isEmpty ? context.title : pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        webCommand = .goBack
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!canGoBack)

                    Button {
                        webCommand = .goForward
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!canGoForward)

                    Button {
                        webCommand = .reload
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }

                    if let url = URL(string: context.urlString) {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                    }
                }
            }
        }
    }
}

private enum TheolWebCommand: Equatable {
    case goBack
    case goForward
    case reload
}

private struct TheolAuthenticatedWebView: UIViewRepresentable {
    let context: TheolWebLaunchContext
    @Binding var estimatedProgress: Double
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var pageTitle: String
    @Binding var command: TheolWebCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context uiContext: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = uiContext.coordinator
        webView.uiDelegate = uiContext.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        uiContext.coordinator.attach(webView: webView)
        uiContext.coordinator.injectCookiesAndLoad(webView: webView, launchContext: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context uiContext: Context) {
        uiContext.coordinator.parent = self
        guard let cmd = command else { return }
        DispatchQueue.main.async {
            self.command = nil
        }
        switch cmd {
        case .goBack:
            if webView.canGoBack { webView.goBack() }
        case .goForward:
            if webView.canGoForward { webView.goForward() }
        case .reload:
            webView.reload()
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: TheolAuthenticatedWebView
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?

        init(parent: TheolAuthenticatedWebView) {
            self.parent = parent
        }

        func attach(webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.parent.estimatedProgress = view.estimatedProgress
                }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.parent.isLoading = view.isLoading
                }
            }
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    if let t = view.title, !t.isEmpty {
                        self?.parent.pageTitle = t
                    }
                }
            }
            backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.parent.canGoBack = view.canGoBack
                }
            }
            forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.parent.canGoForward = view.canGoForward
                }
            }
        }

        func injectCookiesAndLoad(webView: WKWebView, launchContext: TheolWebLaunchContext) {
            guard let targetURL = URL(string: launchContext.urlString) else { return }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

            Task { @MainActor in
                for item in launchContext.cookies {
                    var props: [HTTPCookiePropertyKey: Any] = [
                        .name: item.name,
                        .value: item.value,
                        .domain: item.domain,
                        .path: item.path
                    ]
                    if item.isSecure {
                        props[.secure] = "TRUE"
                    }
                    if let cookie = HTTPCookie(properties: props) {
                        await cookieStore.setCookie(cookie)
                    }
                }
                var req = URLRequest(url: targetURL)
                req.setValue("https://course.buct.edu.cn/meol/welcomepage/student/index.jsp", forHTTPHeaderField: "Referer")
                webView.load(req)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
