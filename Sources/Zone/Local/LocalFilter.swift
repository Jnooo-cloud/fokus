import Foundation
import Observation
import ZoneCore

/// Stands in for FilterController in the local build. The network filter needs a
/// paid Apple Developer team, so this build always uses browser control.
@MainActor @Observable
final class FilterController {
    enum State { case unsigned
        var title: String { "Netzwerkfilter nicht verfügbar" }
    }
    let state = State.unsigned
    let detail = "Der Netzwerkfilter braucht eine Apple-Signatur."
    let isReady = false
    let isSignedBuild = false
    func update(_ document: ZoneDocument) {}
    func refresh() async {}
    func disable() async -> Bool { true }
    func finishPendingUpdates() async -> Bool { true }
}
