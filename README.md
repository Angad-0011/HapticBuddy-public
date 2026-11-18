# HapticBuddy

HapticBuddy is an iOS research prototype for language learning through synchronized haptics, audio, and visual pitch feedback. The app is built around short phrase-level practice and a structured experiment flow for studying whether tactile cues help learners reproduce intonation, stress, and rhythm more accurately.

The repository is named `HapticBuddy`, while the Xcode project and app target are named `HapticAssistant`.

> **Source-only research prototype.** This public copy deliberately excludes the coauthored presentation and all reference voice recordings. It contains no participant recordings or study results. It is not ready for a human-participant study or production use: see [Public-copy limitations](#public-copy-limitations) before collecting any data.

## What The App Does

- Plays reference audio for short phrases and maps intonation to haptic feedback.
- Records the learner's speech and tracks pitch in real time.
- Scores pronunciation using pitch contour, rhythm, stress, and optional ASR-derived metrics.
- Supports a guided experiment flow with pre-test, training, and post-test phases.
- Stores participant metadata and trial logs, then exports results as CSV or JSON.

## Core Features

- Haptic-audio synchronization using `CoreHaptics` and `AVFoundation`
- Real-time pitch detection and contour visualization
- Multiple scoring components, including DTW, rhythm, stress, LSR, F0 RMSE, and optional GOP
- Calibration flow for reducing haptic-audio latency mismatch
- Research-oriented experiment logging and export tools
- Practice and evaluation flows designed for physical iOS devices

## Tech Stack

- Swift 5
- SwiftUI
- CoreHaptics
- AVFoundation
- Speech
- Accelerate
- iOS 17+

## Repository Layout

This project uses a flat source layout inside `HapticAssistant/` rather than separate module folders.

```text
HapticBuddy/
├── HapticAssistant.xcodeproj
├── HapticAssistant/
│   ├── ContentView.swift
│   ├── AudioSessionManager.swift
│   ├── AudioPlayerManager.swift
│   ├── MicrophoneManager.swift
│   ├── PitchDetector.swift
│   ├── HapticEngineManager.swift
│   ├── HapticPatternGenerator.swift
│   ├── HapticViewModel.swift
│   ├── ScoringEngine.swift
│   ├── ExperimentManager.swift
│   ├── DataExportManager.swift
│   ├── phrases.json
│   └── Audio/                 # Add recordings you own locally; not included here
└── README.md
```

## Getting Started

### Requirements

- macOS with Xcode
- iOS 17.0 or later
- A physical iPhone running iOS 17 or later with Core Haptics support for tactile testing. The Xcode target also includes iPad, but targeting a device does not mean it supports haptics. The app checks `supportsHaptics` at runtime; don't use the simulator to judge tactile output.
- Microphone and speech recognition permissions enabled on device

### Setup

```bash
git clone https://github.com/Angad-0011/HapticBuddy-public.git
cd HapticBuddy-public
open HapticAssistant.xcodeproj
```

### Run

1. Open the project and select the **HapticAssistant** target. In **Build Settings**, set **Generate Info.plist File** to **Yes** and clear **Info.plist File** for both Debug and Release; the checked-in settings point to missing files.
2. In the target's **Info** settings, add **Privacy - Microphone Usage Description** (`NSMicrophoneUsageDescription`) and **Privacy - Speech Recognition Usage Description** (`NSSpeechRecognitionUsageDescription`). Describe how the app uses these permissions before trying recording or speech scoring.
3. Under **Signing & Capabilities**, select your development team and use a unique bundle identifier if signing requires it. Select a supported physical iPhone as the run destination.
4. For a one-phrase playback check, make your own recording of “Hello, how are you?” and save it as `HapticAssistant/Audio/hello_how_are_you.wav`. Add the WAV to the app target's **Copy Bundle Resources** so it can be found by the app bundle lookup. Keep the recording local.
5. After reading the [public-copy limitations](#public-copy-limitations), use **Cmd+R** and try that phrase in Practice Mode with your own voice. Do not start a real participant session. These setup steps are based on the project settings and source; device playback and haptics have not been verified.

## App Flow

### Practice Mode

- Choose a phrase from the built-in phrase set.
- Listen to the target audio with or without haptic guidance.
- Record your own attempt.
- Review feedback on intonation, rhythm, and stress.

### Experiment Mode

- Enter participant metadata.
- Run a pre-test with text-only prompts.
- Complete a training block with haptic plus audio support.
- Run a post-test to compare performance after training.
- Export structured logs for later analysis.

### Calibration

- Use the built-in calibration flow to align perceived haptics with audio playback timing.
- Re-run calibration if you change device hardware or notice desynchronization.

## Phrase And Audio Data

The phrase metadata lives in `HapticAssistant/phrases.json`. The corresponding WAV files are **not distributed** in this repository. Add recordings you created or are licensed to redistribute in `HapticAssistant/Audio/` for local experimentation; that directory is ignored by Git.

Each phrase entry includes:

- Display text
- Audio file name
- Intonation type
- Stress indices
- Syllable duration data
- Difficulty, category, and tags

## Scoring And Logging

Pronunciation feedback is computed from multiple signals, including:

- Pitch contour similarity via dynamic time warping
- Rhythm alignment
- Stress realization
- Lexical Stress Ratio
- F0 RMSE
- Optional GOP-style scoring when speech recognition data is available

Experiment logs, participant metadata, and subjective metrics are managed in-app and can be exported for offline analysis.

## Public-copy limitations

- Haptic behavior should be validated on a physical device, not the iOS simulator.
- The current phrase set is intentionally small and geared toward prototype and pilot-study use.
- The app is a research prototype, so the repository currently prioritizes clarity of implementation over package modularity or test coverage.
- The bundled reference audio and coauthored presentation are intentionally excluded. This is a fresh source snapshot; it does not include the private project's Git history.
- The Xcode project references `Info.plist` files that were absent from the source snapshot. Build and permission behavior still need verification.
- **Do not collect real participant data with this version.** A focused security review found that participant IDs with overlapping prefixes can mix audio in export/deletion; deletion can leave raw or derived voice data; the consent text promises anonymization even though entered names can be stored and exported; and CSV/SPSS-style exports do not fully neutralize participant-controlled input. These issues must be fixed and the remaining source reviewed before a real study.
- No license is granted for reuse or redistribution by this repository. Contact the maintainers before using the code beyond what GitHub's terms permit.

## Notes

- If you are cloning the project for the first time, expect to update signing before the app will run on your device.
- No external package manager setup is required; the project uses Apple frameworks directly from Xcode.

## Questions Or Feedback

Open an issue in this repository if you want to discuss the design, experiment flow, or future improvements.
