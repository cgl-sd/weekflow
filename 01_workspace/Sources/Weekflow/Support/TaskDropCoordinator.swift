import Foundation

/// Decodes Weekflow's task drag payload at the AppKit provider boundary and
/// hands the resulting token back to SwiftUI on the main actor.
@MainActor
enum TaskDropCoordinator {
    @discardableResult
    static func handle(
        providers: [NSItemProvider],
        perform: @escaping @MainActor (TaskDragToken) -> Void
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.canLoadObject(ofClass: NSString.self)
        }) else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let rawValue = object as? String,
                  let token = TaskDragToken(token: rawValue) else { return }

            Task { @MainActor in
                perform(token)
            }
        }
        return true
    }
}
