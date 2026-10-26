import AndrofestProtocol
import Foundation

/// The transport advertises and exposes a local byte pipe; it never commits application trust.
@MainActor
protocol PeerLink: AnyObject {
    var onStatus: ((String) -> Void)? { get set }
    var onIntroduction: ((PairingIntroduction) -> Bool)? { get set }
    var onReady: ((UInt16, PairingIntroduction) -> Void)? { get set }
    var onClosed: (() -> Void)? { get set }
    var diagnosticState: String { get }
    var isRunning: Bool { get }
    func start(invitation: PairingInvitation)
    func retryEndpoint()
    func setRealtimeAudio(_ enabled: Bool)
    func stop()
}
