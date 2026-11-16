// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import XCTest
import AVFAudio
@testable import MicRelay

final class OutputSafetyTests: XCTestCase {
    func testStartExplainsSpeakerPermissionWithoutAllowingPlayback() {
        for type in [AVAudioSession.Port.builtInSpeaker, .builtInReceiver] {
            XCTAssertEqual(OutputSafety.startRequirement([port(type)],confirmed:[],speakerEnabled:false),.speakerPermission)
            XCTAssertEqual(OutputSafety.startRequirement([port(type)],confirmed:[],speakerEnabled:true),.ready)
        }
        XCTAssertFalse(OutputSafety.allows([port(.builtInSpeaker)],confirmed:[]))
        XCTAssertEqual(OutputSafety.startRequirement([port(.HDMI)],confirmed:[],speakerEnabled:false),.ready)
    }
    func testStartApprovalIsSpecificToAnExternalRouteAndRejectsUnsupportedMixedOutputs() {
        let usb=port(.usbAudio)
        XCTAssertEqual(OutputSafety.startRequirement([usb],confirmed:[],speakerEnabled:false),.externalConfirmation)
        XCTAssertEqual(OutputSafety.startRequirement([usb],confirmed:[usb.uid],speakerEnabled:false),.ready)
        XCTAssertEqual(OutputSafety.startRequirement([port(.usbAudio,uid:"replacement")],confirmed:[usb.uid],speakerEnabled:false),.externalConfirmation)
        for ports in [[],[port(.airPlay)],[port(.usbAudio),port(.airPlay)],[port(.HDMI),port(.carAudio)]] {
            XCTAssertEqual(OutputSafety.startRequirement(ports,confirmed:[],speakerEnabled:true),.unavailable)
        }
    }
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
