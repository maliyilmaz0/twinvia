import TwinviaProtocol

/// Idempotent call alerts and per-call consent. Status refreshes are not user actions.
struct CallHandoffDecisions {
    struct Decision {
        var alert = false
        var dismiss = false
        var startAudio = false
        var stopAudio = false
    }
    private var alerted: [String] = []
    private var handledApproval: String?
    private var hadConsent = false
    mutating func update(_ call: PhoneCallState?) -> Decision {
        guard let call, call.state != "idle" else {
            handledApproval = nil; hadConsent = false
            return Decision(dismiss: true, stopAudio: true)
        }
        var result = Decision(dismiss: call.state == "active")
        if call.state == "ringing", let token = call.token, !alerted.contains(token) {
            alerted.append(token); alerted = Array(alerted.suffix(32)); result.alert = true
        }
        if call.state == "active", let approval = call.approval, approval != handledApproval {
            handledApproval = approval; hadConsent = true; result.startAudio = true
        } else if call.state == "active", call.approval == nil, hadConsent {
            hadConsent = false; result.stopAudio = true
        }
        return result
    }
    mutating func disconnected() { handledApproval = nil; hadConsent = false }
}
