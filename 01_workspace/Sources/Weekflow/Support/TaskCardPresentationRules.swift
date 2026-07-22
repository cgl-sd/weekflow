enum TaskCardPresentationRules {
    static func shouldPresentAfterToggle(isCurrentlyPresented: Bool) -> Bool {
        !isCurrentlyPresented
    }

    static func shouldPresentDurationAfterToggle(
        isTimerExpanded: Bool,
        isMenuPresented: Bool
    ) -> Bool {
        !isTimerExpanded && !isMenuPresented
    }

    static func shouldLockPersistentPriorityBadge(
        menuIsCurrentlyPresented: Bool,
        priorityShowsPersistently: Bool,
        expandedControlsAreVisible: Bool
    ) -> Bool {
        !menuIsCurrentlyPresented
            && priorityShowsPersistently
            && !expandedControlsAreVisible
    }
}
