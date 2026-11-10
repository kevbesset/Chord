import AppKit

/// A tab dragged out of Chord's windows, from the sidebar or the favorites. Like Arc,
/// dropped anywhere outside Chord it opens in a new window there. An app that takes links
/// (a message, a note, a document) still gets the tab's address; the desktop and Finder
/// do not, they turned it into a shortcut file.
enum TabDragOut {
    /// What a drag of a tab allows outside Chord, where the mouse is now. AppKit asks
    /// again at each move of the drag, so this follows the window under the mouse.
    static func operationOutside() -> NSDragOperation {
        let now = ProcessInfo.processInfo.systemUptime
        // The window list is not free to read: once per 50 ms is enough for a drag.
        if now - lastCheck.time < 0.05 { return lastCheck.operation }
        let operation: NSDragOperation = takesLinks(at: NSEvent.mouseLocation) ? .copy : []
        lastCheck = (now, operation)
        return operation
    }

    private static var lastCheck: (time: TimeInterval, operation: NSDragOperation) = (0, [])

    /// Whether the window under `point` (screen coordinates) belongs to an app that may
    /// take the tab's address: any app but Finder, and not the desktop.
    private static func takesLinks(at point: NSPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        // The window list counts from the top left of the primary screen.
        let flipped = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let under = windows.first { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return frame.contains(flipped)
        }
        guard let pid = under?[kCGWindowOwnerPID as String] as? pid_t else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.apple.finder"
    }

    /// Whether a drag of a tab that nothing took (`operation` empty) ended outside
    /// Chord's windows, and was not cancelled with Escape: the tab then gets a window.
    static func opensWindow(endedAt point: NSPoint, operation: NSDragOperation) -> Bool {
        guard operation.isEmpty, !CGEventSource.keyState(.combinedSessionState, key: 0x35) else { return false }
        return !NSApp.windows.contains { $0.isVisible && $0.level == .normal && $0.frame.contains(point) }
    }
}
