//
//  WeeklyReflectionStore.swift
//  MeetMemento
//
//  Spec 019 R3 / 045 R4: persisted weekly reflection artifact. Counts live
//  in the Swift UI, never in the model.
//

import Foundation

enum WeeklyReflectionStore {
    private static let bodyKey = "weeklyReflection.body"
    private static let weekStartKey = "weeklyReflection.weekStart"
    private static let observationKey = "weeklyReflection.observation"
    private static let citationsKey = "weeklyReflection.citationIDs"
    private static let quietKey = "weeklyReflection.hasNothingToSay"
    private static let ratingKey = "weeklyReflection.rating"
    private static let writingKey = "weeklyReflection.writingNow"

    static let writingDidChange = Notification.Name("weeklyReflection.writingDidChange")
    static let didSave = Notification.Name("weeklyReflection.didSave")

    static var latestBody: String? {
        UserDefaults.standard.string(forKey: bodyKey)
    }

    static var weekStart: Date? {
        UserDefaults.standard.object(forKey: weekStartKey) as? Date
    }

    static var observation: String? {
        UserDefaults.standard.string(forKey: observationKey)
    }

    static var citationIDs: [UUID] {
        (UserDefaults.standard.stringArray(forKey: citationsKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    static var hasNothingToSay: Bool {
        UserDefaults.standard.bool(forKey: quietKey)
    }

    static var rating: ReflectionRating? {
        guard let raw = UserDefaults.standard.string(forKey: ratingKey) else { return nil }
        return ReflectionRating(rawValue: raw)
    }

    static var isWriting: Bool {
        UserDefaults.standard.bool(forKey: writingKey)
    }

    static func isCovered(weekStart: Date) -> Bool {
        guard let stored = self.weekStart else { return false }
        return Calendar(identifier: .iso8601).isDate(stored, equalTo: weekStart, toGranularity: .weekOfYear)
    }

    static func beginWriting() {
        UserDefaults.standard.set(true, forKey: writingKey)
        NotificationCenter.default.post(name: writingDidChange, object: nil)
    }

    static func endWriting() {
        UserDefaults.standard.set(false, forKey: writingKey)
        NotificationCenter.default.post(name: writingDidChange, object: nil)
    }

    static func save(
        body: String,
        weekStart: Date,
        observation: String = "",
        citationIDs: [UUID] = [],
        hasNothingToSay: Bool = false,
        zoneRaw: String = "z0.device",
        promptVersion: String = "weekly@1"
    ) {
        UserDefaults.standard.set(body, forKey: bodyKey)
        UserDefaults.standard.set(weekStart, forKey: weekStartKey)
        UserDefaults.standard.set(observation, forKey: observationKey)
        UserDefaults.standard.set(citationIDs.map(\.uuidString), forKey: citationsKey)
        UserDefaults.standard.set(hasNothingToSay, forKey: quietKey)
        UserDefaults.standard.set(false, forKey: writingKey)
        MementoDataStore.upsertWeeklyReflection(
            body: body,
            weekStart: weekStart,
            observation: observation,
            citationIDs: citationIDs,
            zoneRaw: zoneRaw,
            promptVersion: promptVersion,
            entries: []
        )
        NotificationCenter.default.post(name: didSave, object: nil)
    }

    static func setRating(_ rating: ReflectionRating) {
        UserDefaults.standard.set(rating.rawValue, forKey: ratingKey)
        MementoDataStore.setWeeklyReflectionRating(rating)
        NotificationCenter.default.post(name: didSave, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bodyKey)
        UserDefaults.standard.removeObject(forKey: weekStartKey)
        UserDefaults.standard.removeObject(forKey: observationKey)
        UserDefaults.standard.removeObject(forKey: citationsKey)
        UserDefaults.standard.removeObject(forKey: quietKey)
        UserDefaults.standard.removeObject(forKey: ratingKey)
        UserDefaults.standard.removeObject(forKey: writingKey)
    }
}
