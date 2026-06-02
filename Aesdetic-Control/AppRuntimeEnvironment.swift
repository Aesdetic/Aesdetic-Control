//
//  AppRuntimeEnvironment.swift
//  Aesdetic-Control
//
//  Created by Codex on 2026-06-01.
//

import Foundation

enum AppRuntimeEnvironment {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
