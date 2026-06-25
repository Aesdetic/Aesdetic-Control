import SwiftUI
import UIKit

struct TabBarVisibilityController: UIViewControllerRepresentable {
    var isHidden: Bool = false

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.isTabBarHidden = isHidden
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.isTabBarHidden = isHidden
        uiViewController.applyVisibility()
    }

    final class Controller: UIViewController {
        var isTabBarHidden: Bool = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isOpaque = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyVisibility()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyVisibility()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyVisibility()
        }

        func applyVisibility() {
            if applyVisibilityIfPossible() {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.applyVisibilityIfPossible()
            }
        }

        @discardableResult
        private func applyVisibilityIfPossible() -> Bool {
            guard let tabBarController = tabBarController ?? view.window?.rootViewController?.firstTabBarController else {
                return false
            }

            tabBarController.tabBar.isHidden = isTabBarHidden
            return true
        }
    }
}

private extension UIViewController {
    var firstTabBarController: UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }

        for child in children {
            if let tabBarController = child.firstTabBarController {
                return tabBarController
            }
        }

        return presentedViewController?.firstTabBarController
    }
}
