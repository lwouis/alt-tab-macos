//
//  FilterValidator.swift
//  SwiftyBeaver (iOS)
//
//  Created by Felix Lisczyk on 07.07.19.
//  Copyright © 2019 Sebastian Kreutzberger. All rights reserved.
//

import Foundation

/// FilterValidator is a utility class used by BaseDestination.
/// It encapsulates the filtering logic for excluded, required
/// and non-required filters.
///
/// FilterValidator evaluates a set of filters for a single log
/// entry. It determines if these filters apply to the log entry
/// based on their condition (path, function, message) and their
/// minimum log level.

struct FilterValidator {

    // These are the different filter types that the user can set
    enum ValidationType: CaseIterable {
        case excluded
        case required
        case nonRequired

        func apply(to filters: [FilterType]) -> [FilterType] {
            switch self {
            case .excluded:
                return filters.filter { $0.isExcluded() }
            case .required:
                return filters.filter { $0.isRequired() && !$0.isExcluded() }
            case .nonRequired:
                return filters.filter { !$0.isRequired() && !$0.isExcluded() }
            }
        }
    }

    // Wrapper object for input parameters
    struct Input {
        let filters: [FilterType]
        let level: SwiftyBeaver.Level
        let path: String
        let function: String
        let message: String?
    }

    // Result wrapper object
    enum Result {
        case allFiltersMatch                            // All filters fully match the log entry (condition + minimum log level)
        case someFiltersMatch(PartialMatchData)         // Only some filters fully match the log entry (condition + minimum log level)
        case noFiltersMatchingType                      // There are no filters set for a particular type (excluded, required, nonRequired)

        struct PartialMatchData {
            let fullMatchCount: Int                     // Number of filters that match both the condition and the minimum log level of the log entry
            let conditionMatchCount: Int                // Number of filters that match ONLY the condition of the log entry (path, function, message)
            let logLevelMatchCount: Int                 // Number of filters that match ONLY the minimum log level of the log entry
        }
    }

    static func validate(input: Input, for types: [ValidationType] = ValidationType.allCases) -> [ValidationType: Result] {
        var results = [ValidationType: Result]()
        for type in types {
            let filtersToValidate = type.apply(to: input.filters)

            if filtersToValidate.isEmpty {
                // There are no filters set for this particular type
                results[type] = .noFiltersMatchingType
            } else {
                var fullMatchCount: Int = 0
                var conditionMatchCount: Int = 0
                var logLevelMatchCount: Int = 0

                for filter in filtersToValidate {
                    let filterMatchesCondition = self.filterMatchesCondition(filter, level: input.level, path: input.path, function: input.function, message: input.message)
                    let filterMatchesMinLogLevel = self.filterMatchesMinLogLevel(filter, level: input.level)

                    switch (filterMatchesCondition, filterMatchesMinLogLevel) {
                    // Filter matches both the condition and the minimum log level
                    case (true, true): fullMatchCount += 1
                    // Filter matches only the condition (path, function, message)
                    case (true, false): conditionMatchCount += 1
                    // Filter matches only the minimum log level
                    case (false, true): logLevelMatchCount += 1
                    // Filter does not match the condition nor the minimum log level
                    case (false, false): break
                    }
                }

                if filtersToValidate.count == fullMatchCount {
                    // All filters fully match the log entry
                    results[type] = .allFiltersMatch
                } else {
                    // Only some filters match the log entry
                    results[type] = .someFiltersMatch(.init(fullMatchCount: fullMatchCount, conditionMatchCount: conditionMatchCount, logLevelMatchCount: logLevelMatchCount))
                }
            }
        }

        return results
    }

    private static func filterMatchesCondition(_ filter: FilterType, level: SwiftyBeaver.Level,
                                                path: String, function: String, message: String?) -> Bool {
            let passes: Bool

            switch filter.getTarget() {
            case .Path(_):
                passes = filter.apply(path)

            case .Function(_):
                passes = filter.apply(function)

            case .Message(_):
                guard let message = message else {
                    return false
                }

                passes = filter.apply(message)
            }

            return passes
    }

    private static func filterMatchesMinLogLevel(_ filter: FilterType, level: SwiftyBeaver.Level) -> Bool {
        return filter.reachedMinLevel(level)
    }
}
