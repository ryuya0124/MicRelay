// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import AVFAudio

struct OutputPort: Equatable {
    let uid: String
    let type: AVAudioSession.Port
    let name: String
}

enum OutputSafety {
    static func needsConfirmation(_ port: OutputPort) -> Bool {
        [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .lineOut].contains(port.type)
    }

    static func allows(_ ports: [OutputPort], confirmed: Set<String>, speakerEnabled: Bool = false) -> Bool {
        !ports.isEmpty && ports.allSatisfy {
            $0.type == .headphones || (speakerEnabled && $0.type == .builtInSpeaker)
                || (needsConfirmation($0) && confirmed.contains($0.uid))
        }
    }
}
