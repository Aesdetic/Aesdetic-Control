import SwiftUI
import UIKit

struct TabBarVisibilityController: UIViewControllerRepresentable {
    var isHidden: Bool = false
    var animated: Bool = false

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.configure(isHidden: isHidden, animated: animated)
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.configure(isHidden: isHidden, animated: animated)
        uiViewController.applyVisibility()
    }

    final class Controller: UIViewController {
        var isTabBarHidden: Bool = false
        var animatesTabBarVisibility = false
        private var appliedTabBarHidden: Bool?
        private weak var appliedTabBarController: UITabBarController?

        func configure(isHidden: Bool, animated: Bool) {
            isTabBarHidden = isHidden
            animatesTabBarVisibility = animated
        }

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

            let needsApplication =
                appliedTabBarController !== tabBarController ||
                appliedTabBarHidden != isTabBarHidden ||
                tabBarController.isTabBarHidden != isTabBarHidden
            guard needsApplication else { return true }

            tabBarController.setTabBarHidden(
                isTabBarHidden,
                animated:
                    appliedTabBarController === tabBarController &&
                    appliedTabBarHidden != nil &&
                    animatesTabBarVisibility
            )
            appliedTabBarController = tabBarController
            appliedTabBarHidden = isTabBarHidden
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
