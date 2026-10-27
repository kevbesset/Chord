import Foundation
import os

/// Latency budgets, measured from day one. See docs/PERFORMANCE.md.
///
/// Each interaction opens a signpost interval (visible in Instruments under
/// "Points of Interest") and logs a warning when it runs over budget.
public enum Perf {
    /// Budgets in milliseconds.
    static let budgets: [String: Double] = [
        "commandbar.open": 50,
        "sidebar.toggle": 50,
        "tab.select": 100,
        "space.switch": 100,
        // One step of the sidebar following the fingers: within a 120 Hz frame.
        "space.swipe": 8,
        "peek.open": 100,
        "split.toggle": 100,
        "littlewindow.open": 100,
        "sitecontrols.open": 50,
        "permission.prompt": 50,
        "find.open": 50,
        "extension.popup": 50,
        "app.launch": 1000,
    ]

    /// Every interval's duration by name, while a replay records them
    /// (`engine/scripts/perf-gate.sh`); nil otherwise.
    static var recorded: [String: [Double]]?

    static let signposter = OSSignposter(logHandle: OSLog(subsystem: "app.chord", category: .pointsOfInterest))
    static let logger = Logger(subsystem: "app.chord", category: "perf")

    public struct Interval {
        let name: StaticString
        let state: OSSignpostIntervalState
        let start: UInt64

        /// Ends the interval. Call it once the result is on screen, usually from
        /// `DispatchQueue.main.async` so the layout and display pass are counted.
        public func end() {
            Perf.signposter.endInterval(name, state)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let key = "\(name)"
            Perf.recorded?[key, default: []].append(elapsed)
            if let budget = Perf.budgets[key], elapsed > budget {
                Perf.logger.warning("\(key, privacy: .public) took \(elapsed, format: .fixed(precision: 1)) ms, budget \(budget, format: .fixed(precision: 0)) ms")
            } else {
                Perf.logger.debug("\(key, privacy: .public) took \(elapsed, format: .fixed(precision: 1)) ms")
            }
        }
    }

    public static func begin(_ name: StaticString) -> Interval {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        return Interval(name: name, state: state, start: DispatchTime.now().uptimeNanoseconds)
    }
}
