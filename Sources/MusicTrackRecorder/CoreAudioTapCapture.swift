import Foundation
import AVFoundation
import CoreAudio
import CoreMedia

protocol CoreAudioTapCapturing: AnyObject {
    var onSampleBuffer: ((CMSampleBuffer) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onInterruption: ((String) -> Void)? { get set }
    var onSampleRateChanged: ((Int) -> Void)? { get set }

    func start(sampleRate: Int) async throws
    func updateSampleRate(_ rate: Int) async
    func stop() async
}

@available(macOS 14.2, *)
final class CoreAudioTapCapture: NSObject, CoreAudioTapCapturing {
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onError: ((String) -> Void)?
    var onInterruption: ((String) -> Void)?
    var onSampleRateChanged: ((Int) -> Void)?

    private let queue = DispatchQueue(label: "com.kimi.MusicTrackRecorder.coreaudio-tap")
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private var nextPresentationTime = CMTime.invalid
    private var isRunning = false
    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var outputRateListener: AudioObjectPropertyListenerBlock?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var tapFormatListener: AudioObjectPropertyListenerBlock?

    func start(sampleRate: Int) async throws {
        outputDeviceID = try getProperty(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultOutputDevice,
            AudioObjectID.self
        )
        let process = try await findAppleMusicProcess()
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.name = "Lyrebird Apple Music Tap"

        tapID = try create(description: description)
        aggregateID = try createAggregate(description: description)
        try setSampleRate(sampleRate)
        format = try getProperty(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription.self)
        onSampleRateChanged?(Int(format.mSampleRate))

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            queue
        ) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard status == noErr, let procID else {
            throw TapCaptureError.api(status, "Failed to create the audio callback")
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            throw TapCaptureError.api(startStatus, "Failed to start audio capture")
        }
        isRunning = true
        try installDisruptionListeners()
    }

    func updateSampleRate(_ rate: Int) async {
        guard rate > 0, Int(format.mSampleRate) != rate else { return }
        do {
            await stop()
            try await start(sampleRate: rate)
            NSLog("CoreAudioTap sample rate: \(format.mSampleRate)")
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func stop() async {
        removeDisruptionListeners()
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        isRunning = false
    }

    private func installDisruptionListeners() throws {
        let system = AudioObjectID(kAudioObjectSystemObject)
        defaultOutputListener = try addListener(system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] _, _ in
            self?.onInterruption?("The default output device changed. Stopped and discarded the incomplete recording.")
        }
        outputRateListener = try addListener(outputDeviceID, kAudioDevicePropertyNominalSampleRate) { [weak self] _, _ in
            self?.onInterruption?("The output device sample rate changed. Stopped and discarded the incomplete recording.")
        }
        devicesListener = try addListener(system, kAudioHardwarePropertyDevices) { [weak self] _, _ in
            self?.checkOutputDevicePresence()
        }
        tapFormatListener = try addListener(tapID, kAudioTapPropertyFormat) { [weak self] _, _ in
            self?.checkTapFormat()
        }
    }

    private func addListener(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ handler: @escaping AudioObjectPropertyListenerBlock
    ) throws -> AudioObjectPropertyListenerBlock {
        var address = propertyAddress(selector)
        let status = AudioObjectAddPropertyListenerBlock(object, &address, nil, handler)
        guard status == noErr else {
            throw TapCaptureError.api(status, "Failed to listen for audio device changes")
        }
        return handler
    }

    private func removeDisruptionListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let defaultOutputListener {
            removeListener(system, kAudioHardwarePropertyDefaultOutputDevice, defaultOutputListener)
            self.defaultOutputListener = nil
        }
        if let outputRateListener, outputDeviceID != kAudioObjectUnknown {
            removeListener(outputDeviceID, kAudioDevicePropertyNominalSampleRate, outputRateListener)
            self.outputRateListener = nil
        }
        if let devicesListener {
            removeListener(system, kAudioHardwarePropertyDevices, devicesListener)
            self.devicesListener = nil
        }
        if let tapFormatListener, tapID != kAudioObjectUnknown {
            removeListener(tapID, kAudioTapPropertyFormat, tapFormatListener)
            self.tapFormatListener = nil
        }
    }

    private func removeListener(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ handler: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = propertyAddress(selector)
        AudioObjectRemovePropertyListenerBlock(object, &address, nil, handler)
    }

    private func checkOutputDevicePresence() {
        guard let devices = try? getElements(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDevices,
            AudioObjectID.self
        ), !devices.contains(outputDeviceID) else { return }
        onInterruption?("The current output device disconnected. Stopped and discarded the incomplete recording.")
    }

    private func checkTapFormat() {
        guard let updated = try? getProperty(
            tapID,
            kAudioTapPropertyFormat,
            AudioStreamBasicDescription.self
        ), Int(updated.mSampleRate) != Int(format.mSampleRate) else { return }
        onInterruption?("The audio stream format changed. Stopped and discarded the incomplete recording.")
    }

    private func create(description: CATapDescription) throws -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &id)
        guard status == noErr else {
            throw TapCaptureError.api(status, "Failed to create the process tap")
        }
        return id
    }

    private func createAggregate(description: CATapDescription) throws -> AudioObjectID {
        let properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lyrebird Tap Device",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString]
            ]
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(properties as CFDictionary, &id)
        guard status == noErr else {
            throw TapCaptureError.api(status, "Failed to create the aggregate audio device")
        }
        return id
    }

    private func findAppleMusicProcess() async throws -> AudioObjectID {
        for _ in 0..<30 {
            let objects = try getElements(
                AudioObjectID(kAudioObjectSystemObject),
                kAudioHardwarePropertyProcessObjectList,
                AudioObjectID.self
            )

            for object in objects {
                guard let bundleID = try? getProperty(
                    object,
                    kAudioProcessPropertyBundleID,
                    CFString.self
                ) as String,
                      bundleID == "com.apple.Music" else { continue }
                let output = try getProperty(object, kAudioProcessPropertyIsRunningOutput, UInt32.self)
                if output != 0 {
                    return object
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw TapCaptureError.musicUnavailable
    }

    private func setSampleRate(_ rate: Int) throws {
        guard rate > 0 else { return }
        var value = Float64(rate)
        try setProperty(
            aggregateID,
            kAudioDevicePropertyNominalSampleRate,
            &value
        )
    }

    private func getProperty<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ type: T.Type
    ) throws -> T {
        var address = propertyAddress(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, value)
        guard status == noErr else {
            throw TapCaptureError.api(status, "Failed to read audio property \(selector)")
        }
        return value.pointee
    }

    private func getElements<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ type: T.Type
    ) throws -> [T] {
        var address = propertyAddress(selector)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard status == noErr else {
            throw TapCaptureError.api(status, "Failed to read audio property size \(selector)")
        }
        let count = Int(size) / MemoryLayout<T>.stride
        let values = UnsafeMutablePointer<T>.allocate(capacity: max(count, 1))
        defer { values.deallocate() }
        status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, values)
        guard status == noErr else {
            throw TapCaptureError.api(status, "Failed to read audio property list \(selector)")
        }
        return Array(UnsafeBufferPointer(start: values, count: count))
    }

    private func setProperty<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ value: UnsafeMutablePointer<T>
    ) throws {
        var address = propertyAddress(selector)
        let status = AudioObjectSetPropertyData(
            object,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<T>.size),
            value
        )
        guard status == noErr else {
            throw TapCaptureError.api(status, "Failed to set audio property \(selector)")
        }
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: input)
        )
        let channelCount = Int(format.mChannelsPerFrame)
        guard channelCount > 0 else { return }

        let isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        var interleaved: [Float] = []
        var data = Data()

        if isNonInterleaved {
            guard let first = buffers.first,
                  let firstData = first.mData else { return }
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            interleaved = Array(repeating: 0, count: frames * channelCount)

            for (channel, buffer) in buffers.enumerated() {
                guard let address = buffer.mData else { continue }
                let samples = address.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    interleaved[frame * channelCount + channel] = samples[frame]
                }
            }
            data = interleaved.withUnsafeBytes { Data($0) }
        } else {
            for buffer in buffers {
                guard let address = buffer.mData else { continue }
                data.append(
                    address.assumingMemoryBound(to: UInt8.self),
                    count: Int(buffer.mDataByteSize)
                )
            }
        }

        guard !data.isEmpty,
              let sampleBuffer = makeSampleBuffer(
                data,
                format: format,
                frames: data.count / (channelCount * MemoryLayout<Float>.size)
              ) else { return }
        onSampleBuffer?(sampleBuffer)
    }

    private func makeSampleBuffer(
        _ data: Data,
        format: AudioStreamBasicDescription,
        frames: Int
    ) -> CMSampleBuffer? {
        guard frames > 0 else { return nil }
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        let replaceStatus = data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        guard replaceStatus == noErr else { return nil }

        var formatDescription: CMAudioFormatDescription?
        var description = format
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else { return nil }

        let sampleRate = CMTimeScale(format.mSampleRate)
        let presentation = nextPresentationTime.isNumeric
            ? nextPresentationTime
            : CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1_000_000_000)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: sampleRate),
            presentationTimeStamp: presentation,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = data.count / frames
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { return nil }

        nextPresentationTime = presentation + CMTime(value: Int64(frames), timescale: sampleRate)
        return sampleBuffer
    }
}

private enum TapCaptureError: LocalizedError {
    case api(OSStatus, String)
    case musicUnavailable

    var errorDescription: String? {
        switch self {
        case .api(let status, let message):
            return "\(message) (OSStatus \(status))"
        case .musicUnavailable:
            return "No Apple Music process currently outputting audio was found. Start playback first."
        }
    }
}
