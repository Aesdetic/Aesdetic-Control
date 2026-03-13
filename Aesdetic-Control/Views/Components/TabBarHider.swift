import SwiftUI
import UIKit

struct TabBarHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isOpaque = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hideTabBar()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            hideTabBar()
        }

        private func hideTabBar() {
            tabBarController?.tabBar.isHidden = true
        }
    }
}
