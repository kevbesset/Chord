import AppKit
import Combine

// Spaces and their profiles.
extension BrowserState {
    // MARK: - Spaces

    public func selectSpace(_ space: Space) {
        guard space.id != activeSpaceID else { return }
        activeSpaceID = space.id
        if let tab = selectedTab(in: space) {
            tab.lastSelected = Date()
        }
        for visible in visibleTabs { page(for: visible) }
        enforceSleepPolicy()
        changes.send(.activeSpace)
        scheduleSave()
    }

    public func selectSpace(offset: Int) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let next = ((index + offset) % spaces.count + spaces.count) % spaces.count
        selectSpace(spaces[next])
    }

    /// ⌃1…⌃9, like Arc.
    public func selectSpace(number: Int) {
        guard number >= 1, number <= spaces.count else { return }
        selectSpace(spaces[number - 1])
    }

    /// A new Space has a profile of its own: its own favorites and session. Settings
    /// can group it with other Spaces.
    @discardableResult
    public func addSpace(name: String? = nil, colorHex: String? = nil) -> Space {
        let color = colorHex ?? Theme.spacePalette[spaces.count % Theme.spacePalette.count]
        let space = Space(name: name ?? String(localized: "Space \(spaces.count + 1)", bundle: .chordUI), colorHex: color, profileID: UUID().uuidString)
        spaces.append(space)
        changes.send(.spaces)
        selectSpace(space)
        return space
    }

    public func rename(_ space: Space, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != space.name else { return }
        space.name = trimmed
        changes.send(.spaces)
        scheduleSave()
    }

    /// Gives the Space an emoji, or (nil) its coloured dot back.
    public func setIcon(_ space: Space, icon: String?) {
        let icon = icon.flatMap(Space.icon(from:))
        guard icon != space.icon else { return }
        space.icon = icon
        changes.send(.spaces)
        scheduleSave()
    }

    public func setColor(_ space: Space, hex: String) {
        guard hex != space.colorHex else { return }
        space.colorHex = hex
        changes.send(.spaces)
        scheduleSave()
    }

    /// The profiles in use, each with the Spaces that share it, in Space order.
    public var profiles: [(id: String, spaces: [Space])] {
        var order: [String] = []
        for space in spaces where !order.contains(space.profileID) { order.append(space.profileID) }
        return order.map { id in (id, spaces.filter { $0.profileID == id }) }
    }

    /// Whether the address bar of the Space's profile sits on top of the page, or nil
    /// when the profile follows the default.
    public func addressBarOnTop(for space: Space) -> Bool? {
        addressBarOnTopByProfile[space.profileID]
    }

    /// Moves the address bar of the Space's profile, and so of every Space sharing it.
    public func setAddressBarOnTop(_ onTop: Bool, for space: Space) {
        guard addressBarOnTopByProfile[space.profileID] != onTop else { return }
        addressBarOnTopByProfile[space.profileID] = onTop
        changes.send(.addressBar)
        scheduleSave()
    }

    /// Moves a Space to another profile: it then shows that profile's favorites, and its
    /// tabs load again in that profile's session. A new id gives the Space a profile
    /// of its own.
    public func setProfile(_ space: Space, to profileID: String) {
        guard space.profileID != profileID else { return }
        let used = Set(spaces.map(\.profileID))
        space.profileID = profileID
        for tab in space.allTabs { tab.page = nil }
        dropUnusedProfiles(previouslyUsed: used)
        if space.id == activeSpaceID {
            for visible in visibleTabs { page(for: visible) }
        }
        changes.send(.spaces)
        changes.send(.tabs)
        if space.id == activeSpaceID { changes.send(.selection) }
        scheduleSave()
    }

    /// Deletes a Space and its tabs. The last Space cannot be deleted.
    public func delete(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0 === space }) else { return }
        let used = Set(spaces.map(\.profileID))
        for tab in space.allTabs { tab.page = nil }
        let wasActive = space.id == activeSpaceID
        spaces.remove(at: index)
        dropUnusedProfiles(previouslyUsed: used)
        if wasActive {
            activeSpaceID = spaces[max(0, index - 1)].id
            for visible in visibleTabs { page(for: visible) }
            changes.send(.activeSpace)
        }
        changes.send(.spaces)
        scheduleSave()
    }

    /// What goes with a profile, for the alerts that come before.
    public static let profileDeletionWarning = String(localized: "This is the last Space on its profile: the profile will be deleted too, with its logins, cookies, history, extensions and favorites.", bundle: .chordUI)

    /// Whether the Space is the last one on its profile, which then goes with it (see
    /// `dropUnusedProfiles`). The default profile always stays.
    public func isLastSpace(ofItsProfile space: Space) -> Bool {
        !isPrivate && space.profileID != Space.defaultProfile
            && !spaces.contains { $0 !== space && $0.profileID == space.profileID }
    }

    /// A profile no Space uses any more loses its favorites, and its session (cookies,
    /// history, extensions) is deleted to free its space on disk. The default profile
    /// always stays: it is Chromium's first one.
    func dropUnusedProfiles(previouslyUsed: Set<String>) {
        let used = Set(spaces.map(\.profileID))
        for (profile, tabs) in favoritesByProfile where !used.contains(profile) {
            for tab in tabs { tab.page = nil }
            favoritesByProfile[profile] = nil
        }
        addressBarOnTopByProfile = addressBarOnTopByProfile.filter { used.contains($0.key) }
        guard !isPrivate else { return }
        for profile in previouslyUsed.subtracting(used) where profile != Space.defaultProfile {
            profileEngines[profile] = nil
            engine.deleteProfile?(profile)
        }
    }
}
