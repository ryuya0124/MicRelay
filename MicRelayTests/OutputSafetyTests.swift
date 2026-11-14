// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import XCTest
import AVFAudio
@testable import MicRelay

final class OutputSafetyTests: XCTestCase {
    private func port(_ type: AVAudioSession.Port, uid: String = "test") -> OutputPort {
        OutputPort(uid: uid, type: type, name: "Test")
    }

    func testBuiltInOutputsAreBlockedByDefault() {
        for type in [AVAudioSession.Port.builtInSpeaker, .builtInReceiver, .airPlay, .carAudio] {
            XCTAssertFalse(OutputSafety.allows([port(type)], confirmed: ["test"]))
        }
        XCTAssertFalse(OutputSafety.allows([], confirmed: []))
    }

    func testSpeakerRequiresExplicitOptInAndReceiverStaysBlocked() {
        XCTAssertTrue(OutputSafety.allows([port(.builtInSpeaker)], confirmed: [], speakerEnabled: true))
        XCTAssertFalse(OutputSafety.allows([port(.builtInReceiver)], confirmed: [], speakerEnabled: true))
        XCTAssertFalse(OutputSafety.allows([port(.airPlay)], confirmed: ["test"], speakerEnabled: true))
    }

    func testHeadphonesAndAmbiguousExternalOutputs() {
        XCTAssertTrue(OutputSafety.allows([port(.headphones)], confirmed: []))
        for type in [AVAudioSession.Port.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .lineOut] {
            XCTAssertFalse(OutputSafety.allows([port(type)], confirmed: []))
            XCTAssertTrue(OutputSafety.allows([port(type)], confirmed: ["test"]))
            XCTAssertFalse(OutputSafety.allows([port(type, uid: "replacement")], confirmed: ["test"]))
        }
    }

    func testEveryOutputMustBeAllowed() {
        XCTAssertFalse(OutputSafety.allows([port(.headphones), port(.builtInSpeaker)], confirmed: []))
        XCTAssertFalse(OutputSafety.allows([port(.HDMI), port(.builtInSpeaker)], confirmed: []))
        XCTAssertFalse(OutputSafety.allows([port(.HDMI), port(.airPlay)], confirmed: [], speakerEnabled: true))
    }

    func testHDMIIsAllowedWithoutHeadphoneConfirmationOrSpeakerOptIn() {
        XCTAssertFalse(OutputSafety.needsConfirmation(port(.HDMI)))
        XCTAssertTrue(OutputSafety.allows([port(.HDMI)], confirmed: []))
        XCTAssertTrue(OutputSafety.allows([port(.HDMI, uid: "another-display")], confirmed: []))
        XCTAssertTrue(OutputSafety.allows([port(.HDMI), port(.headphones)], confirmed: []))
        XCTAssertTrue(OutputSafety.allows([port(.HDMI), port(.builtInSpeaker)], confirmed: [], speakerEnabled: true))
    }
}
