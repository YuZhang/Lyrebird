import Foundation
import AVFoundation
import ScreenCaptureKit

final class AudioCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFileStarted: ((String) -> Void)?
    var onFileFinished: ((URL, RecordingQuality) -> Void)?
    var onError: ((String) -> Void)?
    var onNotice: ((String) -> Void)?
    var onCaptureStopped: (() -> Void)?
    var onSampleRateChanged: ((Int) -> Void)?

    private let outputQueue = DispatchQueue(label: "com.kimi.MusicTrackRecorder.audio")
    private let maximumPendingSamples = 512
    private var stream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var tapCapture: (any CoreAudioTapCapturing)?
    private var captureIsActive = false
    private var captureSampleRate = 48_000
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var finalFileURL: URL?
    private var outputDirectory: URL?
    private var trackTitle = "音轨"
    private var trackMetadata: TrackMetadata?
    private var shouldWrite = true
    private var automaticMode = false
    private var recordingFormat: AudioRecordingFormat = .alac
    private var lastSampleEndTime = CMTime.invalid
    private var timestampOffset = CMTime.zero
    private var needsResumeTimestamp = false
    private var pendingSamples: [CMSampleBuffer] = []
    private var quality = RecordingQuality()

    func start(
        outputDirectory: URL,
        title: String,
        automatic: Bool = false,
        format: AudioRecordingFormat = .alac
    ) async throws {
        guard stream == nil && tapCapture == nil else { return }

        if #available(macOS 14.2, *) {
            try await startCoreAudioTap(
                outputDirectory: outputDirectory,
                title: title,
                automatic: automatic,
                format: format
            )
            return
        }

        let filter = try await captureFilter()

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        self.outputDirectory = outputDirectory
        trackTitle = title
        trackMetadata = nil
        shouldWrite = !automatic
        automaticMode = automatic
        recordingFormat = format
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        self.stream = stream
        streamConfiguration = configuration
        captureSampleRate = 48_000

        do {
            try await stream.startCapture()
            captureIsActive = true
            DispatchQueue.main.async {
                self.onSampleRateChanged?(48_000)
            }
        } catch {
            self.stream = nil
            throw CaptureError.captureStartFailed(captureErrorDetails(error))
        }
    }

    @available(macOS 14.2, *)
    private func startCoreAudioTap(
        outputDirectory: URL,
        title: String,
        automatic: Bool,
        format: AudioRecordingFormat
    ) async throws {
        let tap = CoreAudioTapCapture()
        tap.onSampleBuffer = { [weak self] sampleBuffer in
            self?.process(sampleBuffer: sampleBuffer)
        }
        tap.onError = { [weak self] message in
            self?.report(message)
            Task { [weak self] in
                guard let self else { return }
                await self.stop()
                await MainActor.run {
                    self.onCaptureStopped?()
                }
            }
        }
        tap.onInterruption = { [weak self] message in
            self?.reportNotice(message)
            Task { [weak self] in
                guard let self else { return }
                await self.stop()
                await MainActor.run {
                    self.onCaptureStopped?()
                }
            }
        }
        tap.onSampleRateChanged = { [weak self] rate in
            self?.captureSampleRate = rate
            self?.onSampleRateChanged?(rate)
        }
        tapCapture = tap

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        self.outputDirectory = outputDirectory
        trackTitle = title
        trackMetadata = nil
        shouldWrite = !automatic
        automaticMode = automatic
        recordingFormat = format

        do {
            try await tap.start(sampleRate: 48_000)
            captureIsActive = true
        } catch {
            await tap.stop()
            tapCapture = nil
            throw error
        }
    }

    func updateSampleRate(_ requestedRate: Int) async {
        guard requestedRate > 0 else { return }
        let supportedRates: Set<Int> = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        let rate = supportedRates.contains(requestedRate) ? requestedRate : 48_000

        if let tapCapture {
            await tapCapture.updateSampleRate(rate)
            return
        }

        guard let stream, let streamConfiguration,
              writer == nil,
              rate != captureSampleRate else { return }

        do {
            streamConfiguration.sampleRate = rate
            try await stream.updateConfiguration(streamConfiguration)
            captureSampleRate = rate
            DispatchQueue.main.async {
                self.onSampleRateChanged?(rate)
            }
        } catch {
            report("Could not switch the capture sample rate to \(rate) Hz; continuing at \(captureSampleRate) Hz. \(captureErrorDetails(error))")
        }
    }

    func stop() async {
        guard stream != nil || tapCapture != nil else { return }
        shouldWrite = false
        captureIsActive = false

        if let tapCapture {
            await tapCapture.stop()
            self.tapCapture = nil
        }
        if let stream {
            do {
                try await stream.stopCapture()
            } catch {
                report(error.localizedDescription)
            }
            self.stream = nil
        }
        await finishCurrentFile(save: !automaticMode)
    }

    func split(title: String) async {
        await beginTrack(title: title, metadata: nil)
    }

    func beginTrack(title: String, metadata: TrackMetadata?) async {
        guard captureIsActive else { return }
        await withCheckedContinuation { continuation in
            outputQueue.async {
                self.shouldWrite = false
                self.finishCurrentFileOnQueue {
                    self.trackTitle = title
                    self.trackMetadata = metadata
                    self.shouldWrite = true
                    continuation.resume()
                }
            }
        }
    }

    func pauseTrack() async {
        await withCheckedContinuation { continuation in
            outputQueue.async {
                self.shouldWrite = false
                continuation.resume()
            }
        }
    }

    func resumeTrack() async {
        guard captureIsActive else { return }
        await withCheckedContinuation { continuation in
            outputQueue.async {
                self.needsResumeTimestamp = true
                self.shouldWrite = true
                continuation.resume()
            }
        }
    }

    func finishTrack(completed: Bool) async {
        await withCheckedContinuation { continuation in
            outputQueue.async {
                self.shouldWrite = false
                self.finishCurrentFileOnQueue(save: completed) {
                    continuation.resume()
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        process(sampleBuffer: sampleBuffer)
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        outputQueue.async {
            guard self.captureIsActive, self.shouldWrite else { return }

            do {
                if self.writer == nil {
                    try self.startWriterOnQueue(at: sampleBuffer.presentationTimeStamp)
                }
                try self.appendOnQueue(sampleBuffer)
            } catch {
                self.failOnQueue(error.localizedDescription)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureIsActive = false
        self.stream = nil
        report(error.localizedDescription)
        Task {
            await finishCurrentFile(save: !automaticMode)
            await MainActor.run {
                self.onCaptureStopped?()
            }
        }
    }

    private func captureFilter() async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let music = content.applications.first(where: {
            $0.bundleIdentifier == "com.apple.Music"
        }) else {
            throw CaptureError.appleMusicNotRunning
        }

        if let window = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == "com.apple.Music"
        }) {
            return SCContentFilter(desktopIndependentWindow: window)
        }
        if let display = content.displays.first {
            return SCContentFilter(
                display: display,
                including: [music],
                exceptingWindows: []
            )
        }
        throw CaptureError.appleMusicWindowUnavailable
    }

    private func startWriterOnQueue(at presentationTime: CMTime) throws {
        guard let outputDirectory else { throw CaptureError.outputDirectoryUnavailable }
        let finalURL: URL
        if let trackMetadata {
            finalURL = TrackFileNaming.makeURL(metadata: trackMetadata, directory: outputDirectory)
            try FileManager.default.createDirectory(
                at: finalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } else {
            finalURL = TrackFileNaming.makeURL(title: trackTitle, directory: outputDirectory)
        }
        let url = TrackFileNaming.temporaryURL(for: finalURL)
        try? FileManager.default.removeItem(at: url)
        finalFileURL = finalURL
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: recordingFormat.outputSettings(sampleRate: captureSampleRate)
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else { throw CaptureError.audioInputUnavailable }
        writer.add(input)
        writer.metadata = trackMetadata?.avMetadataItems ?? []
        guard writer.startWriting() else {
            throw writer.error ?? CaptureError.writerUnavailable
        }
        writer.startSession(atSourceTime: presentationTime)

        self.writer = writer
        writerInput = input
        lastSampleEndTime = .invalid
        timestampOffset = .zero
        needsResumeTimestamp = false
        pendingSamples.removeAll()
        quality = RecordingQuality()

        let fileName = finalURL.lastPathComponent
        DispatchQueue.main.async {
            self.onFileStarted?(fileName)
        }
    }

    private func appendOnQueue(_ sampleBuffer: CMSampleBuffer) throws {
        let sampleBuffer = adjustedSampleBufferOnQueue(sampleBuffer)
        pendingSamples.append(sampleBuffer)
        quality.maximumBufferedBuffers = max(quality.maximumBufferedBuffers, pendingSamples.count)

        if pendingSamples.count > maximumPendingSamples {
            let dropped = pendingSamples.removeFirst()
            quality.droppedBuffers += 1
            quality.droppedFrames += Int64(CMSampleBufferGetNumSamples(dropped))
        }
        try flushPendingSamplesOnQueue()
    }

    private func adjustedSampleBufferOnQueue(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        if needsResumeTimestamp {
            needsResumeTimestamp = false
            timestampOffset = lastSampleEndTime.isNumeric
                ? lastSampleEndTime - sampleBuffer.presentationTimeStamp
                : .zero
        }
        guard timestampOffset.isNumeric, timestampOffset != .zero else { return sampleBuffer }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: sampleBuffer.presentationTimeStamp + timestampOffset,
            decodeTimeStamp: .invalid
        )
        var adjusted: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjusted
        )
        return status == noErr && adjusted != nil ? adjusted! : sampleBuffer
    }

    private func flushPendingSamplesOnQueue() throws {
        guard let writer, let writerInput else { return }
        guard writer.status == .writing else {
            throw writer.error ?? CaptureError.writerUnavailable
        }

        while writerInput.isReadyForMoreMediaData, !pendingSamples.isEmpty {
            let sampleBuffer = pendingSamples[0]
            guard writerInput.append(sampleBuffer) else {
                throw writer.error ?? CaptureError.sampleAppendFailed
            }
            pendingSamples.removeFirst()
            quality.writtenFrames += Int64(CMSampleBufferGetNumSamples(sampleBuffer))

            let duration = CMSampleBufferGetDuration(sampleBuffer)
            lastSampleEndTime = sampleBuffer.presentationTimeStamp + (duration.isNumeric ? duration : .zero)
        }
    }

    private func discardPendingSamplesOnQueue() {
        for sampleBuffer in pendingSamples {
            quality.droppedBuffers += 1
            quality.droppedFrames += Int64(CMSampleBufferGetNumSamples(sampleBuffer))
        }
        pendingSamples.removeAll()
    }

    private func finishCurrentFile(save: Bool = true) async {
        await withCheckedContinuation { continuation in
            outputQueue.async {
                self.finishCurrentFileOnQueue(save: save) {
                    continuation.resume()
                }
            }
        }
    }

    private func finishCurrentFileOnQueue(
        save requestedSave: Bool = true,
        flushRetries: Int = 100,
        completion: @escaping () -> Void
    ) {
        guard let writer, let url = writer.outputURL as URL?, let finalURL = finalFileURL else {
            pendingSamples.removeAll()
            quality = RecordingQuality()
            finalFileURL = nil
            completion()
            return
        }

        if requestedSave && !pendingSamples.isEmpty && flushRetries > 0 {
            do {
                try flushPendingSamplesOnQueue()
            } catch {
                self.writer = nil
                writerInput = nil
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                finalFileURL = nil
                pendingSamples.removeAll()
                quality = RecordingQuality()
                report(error.localizedDescription)
                completion()
                return
            }

            if !pendingSamples.isEmpty {
                outputQueue.asyncAfter(deadline: .now() + 0.01) {
                    self.finishCurrentFileOnQueue(
                        save: requestedSave,
                        flushRetries: flushRetries - 1,
                        completion: completion
                    )
                }
                return
            }
        }

        if requestedSave && !pendingSamples.isEmpty {
            discardPendingSamplesOnQueue()
        }

        var save = requestedSave
        if save && automaticMode && quality.hasIssues {
            save = false
            report("Dropped audio frames detected; the current track was deleted as an incomplete recording.")
        }
        let finishedQuality = quality

        self.writer = nil
        if save {
            writerInput?.markAsFinished()
        }
        writerInput = nil
        pendingSamples.removeAll()
        quality = RecordingQuality()

        if !save {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            finalFileURL = nil
            lastSampleEndTime = .invalid
            completion()
            return
        }

        guard writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            finalFileURL = nil
            completion()
            return
        }

        if lastSampleEndTime.isNumeric {
            writer.endSession(atSourceTime: lastSampleEndTime)
        }
        lastSampleEndTime = .invalid
        self.finalFileURL = nil
        let expectedMetadata = trackMetadata

        writer.finishWriting {
            if writer.status == .completed {
                do {
                    try FileManager.default.moveItem(at: url, to: finalURL)
                    var completedQuality = finishedQuality
                    if let expectedMetadata {
                        let actual = try? LibraryOrganizer.metadata(for: finalURL)
                        let mismatches = expectedMetadata.readbackMismatches(comparedTo: actual)
                        if !mismatches.isEmpty {
                            completedQuality.metadataWarnings = [
                                "Metadata readback validation failed: \(mismatches.joined(separator: ", "))"
                            ]
                        }
                    }
                    DispatchQueue.main.async {
                        self.onFileFinished?(finalURL, completedQuality)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    self.report("Could not save the final audio file: \(error.localizedDescription)")
                }
            } else {
                try? FileManager.default.removeItem(at: url)
                self.report(writer.error?.localizedDescription ?? CaptureError.writerUnavailable.localizedDescription)
            }
            completion()
        }
    }

    private func failOnQueue(_ message: String) {
        report(message)
        let activeStream = stream
        shouldWrite = false
        captureIsActive = false
        stream = nil
        Task {
            try? await activeStream?.stopCapture()
            await tapCapture?.stop()
            tapCapture = nil
            await finishCurrentFile(save: !automaticMode)
            await MainActor.run {
                self.onCaptureStopped?()
            }
        }
    }

    private func reportNotice(_ message: String) {
        DispatchQueue.main.async {
            self.onNotice?(message)
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async {
            self.onError?(message)
        }
    }
}

enum CaptureError: LocalizedError {
    case screenRecordingPermission
    case appleMusicNotRunning
    case appleMusicWindowUnavailable
    case displayUnavailable
    case outputDirectoryUnavailable
    case audioInputUnavailable
    case writerUnavailable
    case sampleAppendFailed
    case captureStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermission:
            return "Screen & System Audio Recording permission is required. Enable Lyrebird in System Settings; if it is not listed, click + to add it. After granting permission, quit with Cmd+Q and reopen the app."
        case .appleMusicNotRunning:
            return "Apple Music was not detected. Open Music and start playback before recording."
        case .appleMusicWindowUnavailable:
            return "Could not read the Apple Music playback window. Keep Music open and start recording again."
        case .displayUnavailable:
            return "Could not read display information. Check Screen Recording permission."
        case .outputDirectoryUnavailable:
            return "Could not create the output file. Choose the save folder again."
        case .audioInputUnavailable:
            return "Could not initialize the audio encoder."
        case .writerUnavailable:
            return "Could not write the audio file. Check disk space and save folder permissions."
        case .sampleAppendFailed:
            return "Failed to write audio data; recording stopped."
        case .captureStartFailed(let details):
            return "Failed to start system audio capture: \(details)"
        }
    }
}

private func captureErrorDetails(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
}
