# Lyrebird

Lyrebird is a native macOS menu bar app that records Apple Music playback into separate audio files. It captures the decoded audio stream, identifies each song, embeds metadata and artwork, and saves only recordings that it determines are complete.

## Features

- **Automatic track detection and splitting** — reads the current song, artist, album, playback position, duration, and available sample rate from Apple Music.
- **Lossless or compact output** — saves ALAC at 24-bit or AAC at 256 kbps in M4A files.
- **High-resolution recording** — supports 44.1, 48, 88.2, 96, 176.4, and 192 kHz when the source and playback chain provide them.
- **Metadata and artwork** — embeds the title, artist, album, album artist, year, track number, disc number, and cover art when available. Missing catalog fields can be enriched through high-confidence Apple catalog matches.
- **Complete recordings only** — uses temporary `.tmp` files while recording and removes incomplete files after an interrupted or aborted session.
- **Duplicate prevention** — skips songs already present in the save folder and rechecks the folder when files are added or removed.
- **Pause and resume** — pauses writing with Apple Music and continues the same file when playback resumes, without inserting silence.
- **Optional high-res restart** — can restart a song once from the beginning if a higher-resolution stream becomes available after playback starts. This option is off by default.
- **Organized music library** — groups songs into artist and album folders, keeps multi-artist compilations together, and applies track and disc numbers to file names. Invalid file-name characters are replaced safely.
- **Preview before organizing** — reviews moves and name conflicts before changing existing files, with an option to keep both copies and undo the latest organization.
- **Menu bar workflow** — shows recording state in the menu bar and remains available after the main window is closed.
- **English interface and diagnostics** — includes centralized settings, a recording file list, logs, and permission/capture diagnostics.

## Requirements

- macOS 13 or later; macOS 14.2 or later is recommended for Core Audio Process Tap capture.
- The Apple Music app.
- A Swift 5.9-compatible toolchain and Xcode command-line tools for building from source.
- An output device that supports the desired sample rate for high-resolution recording.

On older supported systems, Lyrebird can fall back to ScreenCaptureKit audio capture.

## Quick Start

### 1. Build and install

From the project directory:

```bash
chmod +x setup_local_signing.sh build_app.sh
./setup_local_signing.sh
./build_app.sh
ditto dist/Lyrebird.app /Applications/Lyrebird.app
open /Applications/Lyrebird.app
```

The build script creates:

- `dist/Lyrebird.app`
- `dist/Lyrebird.zip`

`setup_local_signing.sh` creates a persistent local signing identity. Using the same identity across upgrades helps macOS retain permissions. Local keys, certificates, and passwords are excluded from Git. If no local signing identity is configured, the build script uses ad hoc signing.

### 2. Grant permissions

macOS may request one or more of the following permissions:

- **Automation** — reads Apple Music track information and controls playback when a restart is required.
- **Screen & System Audio Recording** — used by the ScreenCaptureKit fallback; Lyrebird does not save screen images.
- **System audio capture** — used for Core Audio Process Tap recording.

If recording still reports a permission error after access is granted, quit Lyrebird completely with **Cmd+Q** and reopen it. **Settings → Capture Diagnostics** can help identify the failing stage.

### 3. Configure recording

Open the gear menu and choose **Settings**:

- Select **Automatic Split** or **Manual** mode.
- Choose **ALAC · 24-bit** or **AAC · 256 kbps**.
- Select the save folder.
- Optionally enable **Restart from Beginning for Hi-Res Audio**.

### 4. Record

1. Click **Start Recording** in the Lyrebird panel.
2. Start playback in Apple Music. Lyrebird can wait if music is not playing yet.
3. In automatic mode, Lyrebird detects the song, creates a temporary file, and saves the final M4A after a complete recording.
4. Use the square **Stop Recording** button to stop. Incomplete automatic recordings are discarded.

Use **Recordings** to inspect saved files and **View Logs** to review completed recordings, skipped songs, warnings, and errors.

### 5. Organize an existing library

Choose **Settings → Organize Songs…** to preview how recordings will be grouped and renamed. Nothing moves until the preview is confirmed. Conflicting files are never overwritten; they can be skipped or kept with a numeric suffix. The latest organization can be undone when the original locations are still available.

## Audio Quality Notes

Lyrebird records Apple Music's **decoded audio stream**, not a direct copy of the original store file. ALAC preserves the captured stream without additional lossy compression, but a 24-bit output file does not prove that the source was 24-bit or that the recording is bit-perfect.

The available sample rate depends on the source, network buffering, Apple Music's stream selection, and the current output device. Raising the output sample rate cannot add detail missing from the source. For high-resolution playback, configure the actual output device in macOS **Audio MIDI Setup**; a USB DAC may need an explicit 96 kHz or 192 kHz output format.

Apple Music may begin with a lower-rate stream and switch to a higher-rate stream after buffering. The optional high-res restart handles this by discarding the incomplete lower-rate recording and restarting once from the beginning. Leave it disabled if uninterrupted listening is more important.

## Tests

Run the full test suite with:

```bash
swift test
```

The tests cover encoding, metadata, file naming, duplicate detection, recording completeness, pause/resume behavior, settings persistence, and library organization.

## Usage Boundary

Use Lyrebird only where permitted by applicable law, copyright requirements, and the Apple Music terms of service. Do not use it for unauthorized copying, distribution, or circumvention of rights management.
