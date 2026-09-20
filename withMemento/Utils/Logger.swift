//
//  Logger.swift
//  MeetMemento
//
//  Minimal logging stub (UI boilerplate).
//

import Foundation
import os.log

/// Minimal logger stub for UI boilerplate
struct AppLogger {
    static let general = "general"
    static let network = "network"
    static let persistent = "persistent"

    /// `@autoclosure` so the interpolated message string is never built in
    /// release, where the body is a no-op (spec 029 Amendment A). Transparent
    /// to callers — every call site keeps passing a plain string expression.
    static func log(_ message: @autoclosure () -> String, category: String = general, type: OSLogType = .default) {
        #if DEBUG
        print("[\(category)] \(message())")
        #endif
    }
}
