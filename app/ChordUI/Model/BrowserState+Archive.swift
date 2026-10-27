import AppKit
import Combine

// The archive of today's tabs, like Arc's.
extension BrowserState {
    // MARK: - Archive

    /// Archives the tabs of today's tabs unused for longer than the setting, every few
    /// minutes and when the setting changes.
    func startArchiving() {
        archiveTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            self?.archiveIdleTabs()
        }
        archiveTimer?.tolerance = 60
        DispatchQueue.main.async { [weak self] in self?.archiveIdleTabs() }
    }

    /// Today's tabs not shown for `ChordSettings.archiveAfter` go to the archive, like
    /// Arc's. A tab on screen in a window, playing sound or on a call stays.
    public func archiveIdleTabs(now: Date = Date()) {
        guard !isPrivate, let delay = ChordSettings().archiveAfter.interval else { return }
        var onScreen = Set(visibleTabs.map(\.id))
        for window in windows where window !== loaded {
            for visible in withWindow(window, { visibleTabs }) { onScreen.insert(visible.id) }
        }
        var archived: [(Tab, Space)] = []
        for space in spaces {
            for tab in space.today where !onScreen.contains(tab.id) && now.timeIntervalSince(tab.lastSelected) > delay {
                if let page = tab.page, page.isAudible == true || page.isCapturingMedia == true || page.hasMedia == true { continue }
                archived.append((tab, space))
            }
        }
        guard !archived.isEmpty else { return }
        for (tab, space) in archived {
            tab.page = nil
            space.today.removeAll { $0 === tab }
            removeFromSplits(tab)
            // A Space whose selected tab goes shows the home page when it comes back.
            if space.selectedTabID == tab.id { space.selectedTabID = nil }
            for window in windows {
                withWindow(window) { if space.selectedTabID == tab.id { space.selectedTabID = nil } }
            }
        }
        addToArchive(archived)
        changes.send(.tabs)
        changes.send(.selection)
        scheduleSave()
    }

    func addToArchive(_ tabs: [(Tab, Space)]) {
        guard !isPrivate else { return }
        let now = Date()
        let added = tabs.filter { $0.0.url != nil }.map { ArchivedTab(snapshot: $0.0.snapshot, spaceID: $0.1.id, date: now) }
        let ids = Set(added.map(\.id))
        archive = added + archive.filter { !ids.contains($0.id) && now.timeIntervalSince($0.date) < Self.archiveKept }
        if archive.count > Self.archiveLimit { archive.removeLast(archive.count - Self.archiveLimit) }
        changes.send(.archive)
    }

    func removeFromArchive(id: UUID) {
        guard archive.contains(where: { $0.id == id }) else { return }
        archive.removeAll { $0.id == id }
        changes.send(.archive)
    }

    /// Opens an archived tab again at the top of today's tabs, in its Space when it still
    /// exists, and selects it.
    public func restore(_ archived: ArchivedTab) {
        let space = spaces.first { $0.id == archived.spaceID } ?? activeSpace
        removeFromArchive(id: archived.id)
        closedTabs.removeAll { $0.snapshot.id == archived.id }
        let tab = Tab(snapshot: archived.snapshot, section: .today)
        tab.lastSelected = Date()
        space.today.insert(tab, at: 0)
        changes.send(.tabs)
        select(tab)
    }

    public func clearArchive() {
        archive = []
        changes.send(.archive)
        scheduleSave()
    }
}
