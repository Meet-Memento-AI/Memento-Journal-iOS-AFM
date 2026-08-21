//
//  WeeklyReflectionStore.swift
//  MeetMemento
//
//  Spec 019 R3: persisted weekly reflection artifact. Counts live in the
//  Swift UI, never in the model.
//

import Foundation

enum WeeklyReflectionStore {
    private static let bodyKey = "weeklyReflection.body"
    private static let weekStartKey = "weeklyReflection.weekStart"

    static var latestBody: String? {
        UserDefaults.standard.string(forKey: bodyKey)
    }

    static var weekStart: Date? {
        UserDefaults.standard.object(forKey: weekStartKey) as? Date
    }

    static func save(body: String, weekStart: Date) {
        UserDefaults.standard.set(body, forKey: bodyKey)
        UserDefaults.standard.set(weekStart, forKey: weekStartKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bodyKey)
        UserDefaults.standard.removeObject(forKey: weekStartKey)
    }
}
