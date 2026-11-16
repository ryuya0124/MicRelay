// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import AVFAudio

struct OutputPort: Equatable {
    let uid: String
    let type: AVAudioSession.Port
    let name: String
}

enum OutputSafety {
    enum StartRequirement { case ready, speakerPermission, externalConfirmation, unavailable }
    static func startRequirement(_ ports: [OutputPort], confirmed: Set<String>, speakerEnabled: Bool) -> StartRequirement {
        let receiver = !ports.isEmpty && ports.allSatisfy { $0.type == .builtInReceiver }
        if allows(ports, confirmed: confirmed, speakerEnabled: speakerEnabled) || (speakerEnabled && receiver) { return .ready }
        if !speakerEnabled && (allows(ports, confirmed: confirmed, speakerEnabled: true) || receiver) { return .speakerPermission }
        let external = Set(ports.filter(needsConfirmation).map(\.uid))
        if !external.isEmpty && allows(ports, confirmed: confirmed.union(external), speakerEnabled: speakerEnabled) { return .externalConfirmation }
        return .unavailable
    }
    static func needsConfirmation(_ port: OutputPort) -> Bool {
        [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .lineOut].contains(port.type)
    }

    static func allows(_ ports: [OutputPort], confirmed: Set<String>, speakerEnabled: Bool = false) -> Bool {
        !ports.isEmpty && ports.allSatisfy {
            $0.type == .headphones || $0.type == .HDMI || (speakerEnabled && $0.type == .builtInSpeaker)
                || (needsConfirmation($0) && confirmed.contains($0.uid))
        }
    }
}
