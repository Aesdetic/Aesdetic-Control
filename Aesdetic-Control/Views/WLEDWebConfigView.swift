import SwiftUI
import WebKit

struct WLEDWebConfigView: View {
	let url: URL
	@State private var progress: Double = 0
	@State private var canGoBack: Bool = false
	@State private var canGoForward: Bool = false

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				Button(action: { NotificationCenter.default.post(name: .webGoBack, object: nil) }) {
					Image(systemName: "chevron.left").foregroundColor(canGoBack ? .white : .white.opacity(0.4))
				}.disabled(!canGoBack)
				Button(action: { NotificationCenter.default.post(name: .webGoForward, object: nil) }) {
					Image(systemName: "chevron.right").foregroundColor(canGoForward ? .white : .white.opacity(0.4))
				}.disabled(!canGoForward)
				Spacer()
				Button(action: { NotificationCenter.default.post(name: .webReload, object: nil) }) {
					Image(systemName: "arrow.clockwise").foregroundColor(.white)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
			.background(Color.clear)

			ProgressView(value: progress)
				.progressViewStyle(.linear)
				.tint(.white)
				.opacity(progress < 1 ? 1 : 0)
				.animation(.easeInOut(duration: 0.2), value: progress)

			WebView(url: url, progress: $progress, canGoBack: $canGoBack, canGoForward: $canGoForward)
		}
		.background(Color.clear.ignoresSafeArea())
	}
}

private struct WebView: UIViewRepresentable {
	let url: URL
	@Binding var progress: Double
	@Binding var canGoBack: Bool
	@Binding var canGoForward: Bool

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeUIView(context: Context) -> WKWebView {
		let webView = WKWebView(frame: .zero)
		webView.navigationDelegate = context.coordinator
		webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
		webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
		webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
		webView.load(URLRequest(url: url))
		NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.goBack), name: .webGoBack, object: nil)
		NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.goForward), name: .webGoForward, object: nil)
		NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.reload), name: .webReload, object: nil)
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		// no-op
	}

	class Coordinator: NSObject, WKNavigationDelegate {
		var parent: WebView
		init(_ parent: WebView) { self.parent = parent }

		override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
			guard let webView = object as? WKWebView else { return }
			if keyPath == #keyPath(WKWebView.estimatedProgress) {
				parent.progress = webView.estimatedProgress
			} else if keyPath == #keyPath(WKWebView.canGoBack) {
				parent.canGoBack = webView.canGoBack
			} else if keyPath == #keyPath(WKWebView.canGoForward) {
				parent.canGoForward = webView.canGoForward
			}
		}

		@objc func goBack() {
			(parentView as? WKWebView)?.goBack()
		}
		@objc func goForward() {
			(parentView as? WKWebView)?.goForward()
		}
		@objc func reload() {
			(parentView as? WKWebView)?.reload()
		}

		private var parentView: UIView? {
			// WKWebView reference from notification not passed; rely on KVO target
			// This is a simple approach: search the key window for WKWebView
			return UIApplication.shared.connectedScenes
				.compactMap { ($0 as? UIWindowScene)?.keyWindow }
				.first?
				.rootViewController?.view.subviews.first(where: { $0 is WKWebView })
		}
	}
}

private extension Notification.Name {
	static let webGoBack = Notification.Name("WLEDWebViewGoBack")
	static let webGoForward = Notification.Name("WLEDWebViewGoForward")
	static let webReload = Notification.Name("WLEDWebViewReload")
}


