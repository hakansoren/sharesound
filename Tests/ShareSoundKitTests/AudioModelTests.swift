import CoreAudio
import Testing
@testable import ShareSoundKit

@MainActor
@Suite("Models and CoreAudio mapping")
struct AudioModelTests {

    @Test("Transport type codes map onto the model", arguments: [
        (raw: kAudioDeviceTransportTypeBuiltIn, expected: TransportType.builtIn),
        (raw: kAudioDeviceTransportTypeBluetooth, expected: .bluetooth),
        (raw: kAudioDeviceTransportTypeBluetoothLE, expected: .bluetooth),
        (raw: kAudioDeviceTransportTypeUSB, expected: .usb),
        (raw: kAudioDeviceTransportTypeAirPlay, expected: .airPlay),
        (raw: kAudioDeviceTransportTypeHDMI, expected: .hdmi),
        (raw: kAudioDeviceTransportTypeDisplayPort, expected: .displayPort),
        (raw: kAudioDeviceTransportTypeThunderbolt, expected: .thunderbolt),
        (raw: kAudioDeviceTransportTypeAggregate, expected: .virtual),
        (raw: UInt32(0), expected: .unknown),
    ])
    func mapsTransportTypes(raw: UInt32, expected: TransportType) {
        #expect(TransportType(coreAudioTransportType: raw) == expected)
    }

    @Test("Wireless transports are flagged")
    func identifiesWirelessTransports() {
        #expect(TransportType.bluetooth.isWireless)
        #expect(TransportType.airPlay.isWireless)
        #expect(TransportType.usb.isWireless == false)
        #expect(TransportType.builtIn.isWireless == false)
    }

    @Test("Every transport has an icon and a label", arguments: TransportType.allCases)
    func everyTransportHasPresentation(transport: TransportType) {
        #expect(transport.symbolName.isEmpty == false)
        #expect(transport.localizedLabel.isEmpty == false)
    }

    @Test("Aggregate devices cannot join a share")
    func aggregateDevicesAreNotEligible() {
        #expect(AudioDevice.stub(id: 1, isAggregate: true).isEligibleForSharing == false)
        #expect(AudioDevice.stub(id: 2).isEligibleForSharing)
    }

    @Test("The shared output demands at least two members")
    func aggregateControllerRequiresTwoMembers() {
        let controller = CoreAudioAggregateController(uidGenerator: { "test-uid" })
        let device = AudioDevice.stub(id: 1)

        #expect(throws: ShareSoundError.needsAtLeastTwoDevices) {
            _ = try controller.createAggregate(name: "Test", members: [device], master: device)
        }
    }

    @Test("The session reports its first member as master")
    func sessionReportsMaster() {
        let session = ShareSession(
            aggregateDeviceID: 100,
            memberDeviceIDs: [7, 8],
            previousDefaultDeviceID: 3
        )

        #expect(session.masterDeviceID == 7)
        #expect(SessionState.sharing(session).isSharing)
        #expect(SessionState.idle.isSharing == false)
        #expect(SessionState.idle.session == nil)
    }
}
