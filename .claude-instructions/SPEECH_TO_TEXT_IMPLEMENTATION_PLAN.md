# Speech-to-Text Implementation Plan (AddEntryView Microphone FAB)

## Goal

Implement native iOS speech-to-text so that when the user taps the microphone FAB on AddEntryView and speaks, the transcribed text is inserted into the "Write your thoughts" body field. Use Apple's Speech framework and AVFoundation for the best possible transcription with native iOS features.

## Current State

- **SpeechService** (`withMemento/Services/SpeechService.swift`): Stub only. `startRecording()` / `stopRecording()` are no-ops. `transcribedText` is never set. `currentDuration` is never updated.
- **AddEntryView**: Already wires the FAB to `SpeechService`; on stop (when `isRecording` goes from true to false), it calls `insertTranscribedText(speechService.transcribedText)` to append the transcript to the body `TextEditor`. Alerts for permission denied and recording failed are in place.
- **Info.plist**: Already has `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.

## Native iOS Stack (Apple Recommendations)

1. **Speech framework** – `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`, `SFSpeechRecognitionTask` for on-device or server-based recognition.
2. **AVFoundation** – `AVAudioEngine`, `AVAudioInputNode`, `AVAudioSession` for capturing microphone audio and feeding it to the recognizer.
3. **Permissions** – `SFSpeechRecognizer.requestAuthorization` (speech) and `AVAudioSession.requestRecordPermission` (microphone). Both are required for STT.

## Implementation Plan

### Phase 1: Permissions and Availability

**File:** `withMemento/Services/SpeechService.swift`

1. **Import frameworks**
   - Add `import Speech` and `import AVFoundation`.

2. **Request Speech recognition authorization**
   - In `requestAuthorization()` (or a dedicated method called before starting):
     - Call `SFSpeechRecognizer.requestAuthorization { status in ... }` and map to your `AuthorizationStatus` (e.g. `notDetermined` / `denied` / `authorized`).
     - Update `@Published var authorizationStatus` on the main actor.
   - Optionally also request **microphone** permission via `AVAudioSession.sharedInstance().requestRecordPermission`. If denied, throw `SpeechError.permissionDenied` from `startRecording()`.

3. **Check availability**
   - Before starting, ensure `SFSpeechRecognizer(locale: Locale.current)` (or a fixed locale like `.current`) is not nil and `isAvailable`. If unavailable (e.g. offline, locale not supported), throw `SpeechError.notAvailable` and set `errorMessage`.

4. **Expose a single “prepare” flow**
   - Add a method such as `func prepareForRecording() async throws` that:
     - Requests speech authorization if not determined.
     - Requests microphone permission if not granted.
     - Checks recognizer availability.
     - Sets `authorizationStatus` and throws if denied or unavailable.
   - Call this from `startRecording()` at the beginning, or call it once when the user first opens AddEntryView (optional).

### Phase 2: Audio Capture with AVAudioEngine

**File:** `withMemento/Services/SpeechService.swift`

1. **AVAudioSession configuration**
   - In `startRecording()`, configure the shared session for recording:
     - `AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])` (or `.default` if you prefer).
     - `setActive(true)`.
   - Use a do/catch and set `errorMessage` / throw if activation fails (e.g. another app holding the session).

2. **Create and start AVAudioEngine**
   - Add private properties, e.g. `private var audioEngine: AVAudioEngine?` and `private var inputNode: AVAudioInputNode?`.
   - In `startRecording()`:
     - Instantiate `AVAudioEngine()`, get `inputNode = audioEngine.inputNode`.
     - Choose a format suitable for the recognizer (typically the input node’s output format, or a 16 kHz mono format if required by the API – see Apple’s “Transcribing Speech to Text” sample).
     - Install a tap on the input node and append the buffers to the recognition request (see Phase 3). Install the tap **before** `audioEngine.prepare()` and `audioEngine.start()`.
   - On failure to start the engine, set `errorMessage`, throw, and ensure `isRecording` is set back to false.

3. **Duration timer**
   - Use a `Timer` or a simple `Task` that sleeps and updates `currentDuration` on the main actor (e.g. every 0.1 s) while `isRecording` is true. Start in `startRecording()`, invalidate/stop in `stopRecording()`.

### Phase 3: Speech Recognition (SFSpeechRecognizer + Buffer Request)

**File:** `withMemento/Services/SpeechService.swift`

1. **Create SFSpeechRecognizer**
   - Use `SFSpeechRecognizer(locale: Locale.current)` (or a specific locale). Store in a private property or create when needed. Guard that it is non-nil and `isAvailable` before starting.

2. **Create SFSpeechAudioBufferRecognitionRequest**
   - Create a `SFSpeechAudioBufferRecognitionRequest()`.
   - Set `shouldReportPartialResults = true` if you want live (partial) transcription; set to `false` if you only want the final result when recording stops.
   - Prefer `taskHint = .dictation` for free-form journal text.
   - Configure the audio format to match what you pass from the tap (same format as the buffer you append).

3. **Install tap and feed buffers**
   - In the input node’s tap block:
     - Append `AVAudioPCMBuffer` to the request with `request.append(buffer)`.
     - Do this on a consistent queue (e.g. a dedicated serial queue or the same queue the recognizer uses) to avoid threading issues.
   - Start the recognition task with `recognizer.recognitionTask(with: request) { [weak self] result, error in ... }`.

4. **Recognition task callback**
   - On the main actor (or dispatch to MainActor), update state:
     - If `result?.isFinal == true`, set `transcribedText = result?.bestTranscription.formattedString ?? ""` (and clear any partial state if you use it).
     - If using partial results, you can store the latest partial string in a separate `@Published` property (e.g. `partialTranscribedText`) so the UI can show live text; AddEntryView would then need to bind to that for live display, or you only commit on stop.
   - On error, set `errorMessage`, and consider stopping the task and engine.
   - When the task ends (completion handler or `cancel()`), clean up: remove tap, stop engine, set `isProcessing = false` if you use it, and ensure `transcribedText` holds the final transcript for the caller.

5. **Stop recording**
   - In `stopRecording()`:
     - Call `request.endAudio()` so the recognizer finalizes.
     - Cancel the recognition task if needed.
     - Remove the tap from the input node, then call `audioEngine?.stop()`.
     - Deactivate the audio session: `AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)`.
     - Stop the duration timer and set `currentDuration = 0`.
     - Set `isRecording = false`.
     - Ensure the final result is in `transcribedText` (from the task callback when `isFinal` or when the task completes). If you only use partial results, copy the last partial into `transcribedText` when stopping so AddEntryView’s `insertTranscribedText(speechService.transcribedText)` still works.

### Phase 4: AddEntryView Integration (Minimal Changes)

**File:** `withMemento/Views/Journal/AddEntryView.swift`

1. **Keep existing flow**
   - Leave `onChange(of: speechService.isRecording)` as is: when transitioning from true to false, call `insertTranscribedText(speechService.transcribedText)` so the final transcript is appended to the body field with `"\n\n"` when body is non-empty.

2. **Optional: live transcription**
   - If you implement partial results and want text to appear **while** the user is speaking, add a binding or observer for `speechService.partialTranscribedText` and temporarily show/merge it into the body (e.g. body = existingText + "\n\n" + partial). On stop, replace that with the final `transcribedText` and clear partial. This is optional; the plan’s minimum is final text on stop.

3. **Error handling**
   - Keep showing `showPermissionDenied` for `SpeechError.permissionDenied` and `showSTTError` with `speechService.errorMessage` for other errors. Ensure `SpeechService` sets `errorMessage` for recognizer/engine/session errors so the user sees a clear message.

4. **Processing state**
   - Keep using `speechService.isProcessing` to show the spinner in the FAB and disable the button while processing. Set `isProcessing = true` when starting the recognition task and `false` when the task finishes or when stopping.

### Phase 5: Threading and Lifecycle

1. **Main actor**
   - All `@Published` updates and UI-related state (`isRecording`, `transcribedText`, `errorMessage`, `currentDuration`, `isProcessing`) must be updated on the main actor (e.g. `await MainActor.run { ... }` or mark the class as `@MainActor` if appropriate).

2. **Recognition task callback**
   - From the completion handler of `recognitionTask(with: request)`, dispatch to the main actor before updating `transcribedText`, `errorMessage`, or `isProcessing`.

3. **Cleanup**
   - On stop or on error, always: end the request, cancel the task, remove the tap, stop the engine, and deactivate the session so the microphone is released and other apps can use it.

### Phase 6: Testing and Edge Cases

1. **Locale**
   - Use `Locale.current` for the recognizer unless you need a fixed language. Handle the case where that locale is not supported by SFSpeechRecognizer (fallback list or show “not available”).

2. **Background**
   - On-device recognition can continue in background in some configurations; server-based may have limits. Prefer on-device if possible for privacy and offline. Document behavior when app goes to background (e.g. stop recording and commit transcript).

3. **Long sessions**
   - Apple recommends limiting very long recognition sessions; consider a max duration (e.g. 60 seconds) and auto-stop, then append and optionally start a new task if the user keeps the FAB pressed (or just stop once and require another tap).

4. **Permissions**
   - If the user denies speech or microphone, show the existing alerts and do not start the engine. Optionally prompt once at first use with a short explanation before requesting authorization.

## File Summary

| File | Action |
|------|--------|
| `withMemento/Services/SpeechService.swift` | Implement full STT: imports (Speech, AVFoundation), SFSpeechRecognizer, SFSpeechAudioBufferRecognitionRequest, AVAudioEngine tap, recognition task callback, requestAuthorization + microphone permission, duration timer, stop/cleanup, set transcribedText and errorMessage on main actor. |
| `withMemento/Views/Journal/AddEntryView.swift` | No structural change required; optional: add live partial text binding. Keep onChange(isRecording) and insertTranscribedText(transcribedText). |
| `Info.plist` | Already has NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription; no change. |

## Order of Work

1. Add Speech and AVFoundation imports and permission/availability checks in SpeechService.
2. Implement AVAudioSession setup and AVAudioEngine tap in startRecording(), feeding buffers to a SFSpeechAudioBufferRecognitionRequest and starting a recognition task.
3. In the task callback, update transcribedText (and optionally partialTranscribedText) on the main actor; handle errors and isFinal.
4. Implement stopRecording(): endAudio(), cancel task, remove tap, stop engine, deactivate session, update duration and isRecording.
5. Add duration timer and isProcessing updates.
6. Test on device (recognition often requires a real device); verify permissions and that AddEntryView body receives the transcript on stop.

## Reference

- Apple tutorial (conceptual): [Transcribing Speech to Text](https://developer.apple.com/tutorials/app-dev-training/transcribing-speech-to-text)
- Speech framework: `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`, `SFSpeechRecognitionTask`
- AVFoundation: `AVAudioEngine`, `AVAudioInputNode`, `AVAudioSession`, `AVAudioPCMBuffer`
