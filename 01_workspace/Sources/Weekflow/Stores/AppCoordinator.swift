import Foundation
import Observation

@MainActor
@Observable
final class NavigationStore {
    var destination: AppDestination
    var workspaceView: WorkspaceView

    init(destination: AppDestination = .home, workspaceView: WorkspaceView = .board) {
        self.destination = destination
        self.workspaceView = workspaceView
    }
}

/// Per-window coordinator. A command without an explicit target is bound by
/// CommandRouter to the active scene, preventing duplicate multi-window work.
@MainActor
@Observable
final class AppCoordinator {
    let sceneID: UUID
    let navigation: NavigationStore
    let commands: CommandRouter

    init(
        sceneID: UUID = UUID(),
        navigation: NavigationStore = NavigationStore(),
        commands: CommandRouter = .shared
    ) {
        self.sceneID = sceneID
        self.navigation = navigation
        self.commands = commands
    }

    func activate() { commands.sceneBecameActive(sceneID) }

    func accepts(_ routed: RoutedAppCommand) -> Bool {
        routed.targetSceneID == nil || routed.targetSceneID == sceneID
    }
}
