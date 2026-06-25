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
		context.coordinator.attach(to: webView)
		webView.load(URLRequest(url: url))
		NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.goBack), name: .webGoBack, object: nil)
		NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.goForward), name: .webGoForward, object: nil)
		NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.reload), name: .webReload, object: nil)
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		// no-op
	}

	static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
		webView.stopLoading()
		webView.navigationDelegate = nil
		coordinator.detach()
	}

	class Coordinator: NSObject, WKNavigationDelegate {
		var parent: WebView
		private weak var webView: WKWebView?
		private var isObserving = false

		init(_ parent: WebView) { self.parent = parent }

		deinit {
			detach()
		}

		func attach(to webView: WKWebView) {
			self.webView = webView
			guard !isObserving else { return }
			webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
			webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
			webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
			isObserving = true
		}

		func detach() {
			NotificationCenter.default.removeObserver(self)
			guard isObserving, let webView else { return }
			webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
			webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
			webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
			isObserving = false
		}

		override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
			guard let webView = object as? WKWebView else { return }
			let progress = webView.estimatedProgress
			let canGoBack = webView.canGoBack
			let canGoForward = webView.canGoForward
			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				if keyPath == #keyPath(WKWebView.estimatedProgress) {
					self.parent.progress = progress
				} else if keyPath == #keyPath(WKWebView.canGoBack) {
					self.parent.canGoBack = canGoBack
				} else if keyPath == #keyPath(WKWebView.canGoForward) {
					self.parent.canGoForward = canGoForward
				}
			}
		}

		@objc func goBack() {
			webView?.goBack()
		}
		@objc func goForward() {
			webView?.goForward()
		}
		@objc func reload() {
			webView?.reload()
		}
	}
}

private extension Notification.Name {
	static let webGoBack = Notification.Name("WLEDWebViewGoBack")
	static let webGoForward = Notification.Name("WLEDWebViewGoForward")
	static let webReload = Notification.Name("WLEDWebViewReload")
}

