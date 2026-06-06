import ServiceManagement

public protocol LaunchAtLoginControlling: Sendable {
    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws
}

public struct LaunchAtLoginService: LaunchAtLoginControlling {
    public init() {}

    public func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

public struct LaunchAtLoginPreferenceUpdater: Sendable {
    private let controller: any LaunchAtLoginControlling

    public init(controller: any LaunchAtLoginControlling = LaunchAtLoginService()) {
        self.controller = controller
    }

    public func preferencesByApplying(_ isEnabled: Bool, to preferences: Preferences) throws -> Preferences {
        try controller.setLaunchAtLoginEnabled(isEnabled)
        var updatedPreferences = preferences
        updatedPreferences.launchAtLoginEnabled = isEnabled
        return updatedPreferences
    }
}
