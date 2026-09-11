# iOS Gázóra-leolvasó Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iOS 26+ iPhone application that captures a gas-meter photo, proposes the register window and eight digits locally, requires manual approval, and synchronizes verified readings to the existing Home Assistant `gas_photo` integration.

**Architecture:** A SwiftUI app owns presentation and calls focused services through protocols: photo/archive, inference, reading repository, credentials, Home Assistant transport, and training. SwiftData stores only local audit metadata; original images and activated model files are kept in Application Support. Objective-C++ bridges Swift to ONNX Runtime Mobile inference and training APIs so business rules stay unit-testable in Swift.

**Tech Stack:** Swift 6.3, SwiftUI, SwiftData, AVFoundation, ImageIO, CryptoKit, Security/Keychain, AuthenticationServices, URLSession, XCTest, CocoaPods (`onnxruntime-objc` and `onnxruntime-training-c`), Objective-C++.

**Spec:** `docs/superpowers/specs/2026-09-11-ios-gas-meter-reader-design.md`

## Global Constraints

- Support iOS 26 and newer only; build and run against an iPhone 14 Pro Max simulator and physical iPhone 14 Pro Max.
- Bundle the existing `window-detector/weights/best.onnx` and `digit-classifier/weights/active.onnx` unchanged for inference.
- All recognition, candidate training, original photos, labels, and models remain local to the iPhone; never send photos or labels to Home Assistant or any other service.
- Recognition is always a suggestion. No reading may enter `pendingSync` or call Home Assistant before explicit user approval.
- Preserve the original captured image and its ImageIO capture timestamp; do not let approval edit the timestamp.
- Use one `gas_main` meter identifier. Retain eight display digits, remove leading zeroes only for the decimal value sent to Home Assistant.
- Store OAuth access/refresh tokens only in the iOS Keychain. Never log a token or persist it in SwiftData, files, test fixtures, screenshots, or diagnostics.
- Import with `gas_photo.import_readings?return_response`, then verify the same fields via `gas_photo.get_readings?return_response` from `service_response` before setting `synced`.
- Candidate training needs at least 40 approved, varied photo labels; 80/10/10 photo-group split; no automatic activation; 90% minimum digit top-1; no high-confidence regression; explicit activation and rollback.
- Apply TDD for every behavior change: write and run the focused failing XCTest first, make the smallest implementation, re-run the focused test, then run the suite.

---

### Task 1: Bootstrap the iOS workspace and dependency boundary

**Files:**
- Create: `GasPhotoIOS.xcodeproj/project.pbxproj`
- Create: `GasPhotoIOS.xcodeproj/xcshareddata/xcschemes/GasPhotoIOS.xcscheme`
- Create: `Podfile`, `Podfile.lock`
- Create: `GasPhotoIOS/App/GasPhotoIOSApp.swift`
- Create: `GasPhotoIOS/App/AppContainer.swift`
- Create: `GasPhotoIOS/App/RootView.swift`
- Create: `GasPhotoIOSTests/AppContainerTests.swift`

**Interfaces:**
- Produces: `AppContainer` with injectable `readingRepository`, `photoArchive`, `inferenceService`, `credentialStore`, `homeAssistantClient`, and `trainingService` dependencies.
- Produces: application target `GasPhotoIOS` and XCTest bundle `GasPhotoIOSTests`.

- [ ] **Step 1: Write the failing container composition test.**

```swift
func testLiveContainerUsesDistinctConcreteServices() {
    let container = AppContainer.live()
    XCTAssertFalse(container.readingRepository is InMemoryReadingRepository)
    XCTAssertFalse(container.inferenceService is StubInferenceService)
}
```

- [ ] **Step 2: Run the target test to verify it fails because the application module is absent.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/AppContainerTests/testLiveContainerUsesDistinctConcreteServices`

Expected: FAIL because the workspace, scheme, or `AppContainer` does not exist.

- [ ] **Step 3: Create the Xcode app/test targets and CocoaPods dependencies.**

```ruby
platform :ios, '26.0'
use_frameworks! :linkage => :static
target 'GasPhotoIOS' do
  pod 'onnxruntime-objc'
  pod 'onnxruntime-training-c'
end
```

```swift
@main
struct GasPhotoIOSApp: App {
    private let container = AppContainer.live()
    var body: some Scene { WindowGroup { RootView(container: container) } }
}
```

Create one manual `.xcodeproj` application target, add the Pods workspace, set `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, enable `SWIFT_STRICT_CONCURRENCY = complete`, and add all later `GasPhotoIOS/**` sources through synchronized folders. Keep the bundle identifier in an `.xcconfig` file, not source code.

- [ ] **Step 4: Implement the smallest container that satisfies the test.**

```swift
struct AppContainer {
    let readingRepository: any ReadingRepository
    let photoArchive: any PhotoArchive
    let inferenceService: any InferenceService
    let credentialStore: any CredentialStore
    let homeAssistantClient: any HomeAssistantClient
    let trainingService: any TrainingService
}

struct RootView: View {
    let container: AppContainer
    var body: some View { Text("Gázóra leolvasás") }
}
```

- [ ] **Step 5: Re-run the target test, then build the app.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/AppContainerTests`

Run: `xcodebuild build -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max'`

Expected: PASS and `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit the bootstrap.**

```bash
git add GasPhotoIOS.xcodeproj Podfile Podfile.lock GasPhotoIOS GasPhotoIOSTests
git commit -m "feat: bootstrap iOS gas photo app"
```

### Task 2: Define the reading domain and local audit persistence

**Files:**
- Create: `GasPhotoIOS/Domain/Reading.swift`
- Create: `GasPhotoIOS/Domain/ReadingValidator.swift`
- Create: `GasPhotoIOS/Data/SwiftDataReadingRepository.swift`
- Create: `GasPhotoIOSTests/ReadingValidatorTests.swift`
- Create: `GasPhotoIOSTests/SwiftDataReadingRepositoryTests.swift`

**Interfaces:**
- Produces: `MeterReading`, `ReadingStatus`, `NormalizedRect`, `DigitProposal`, `ReadingValidator`, and `ReadingRepository`.

- [ ] **Step 1: Write failing validator tests for display form, upload value, and approval transition.**

```swift
func testApprovalPreservesEightDigitsButNormalizesUploadValue() throws {
    let reading = try ReadingValidator.approvedDigits("01817.759")
    XCTAssertEqual(reading.displayValue, "01817.759")
    XCTAssertEqual(reading.uploadValue, "1817.759")
}

func testApprovalRejectsWrongDigitShape() {
    XCTAssertThrowsError(try ReadingValidator.approvedDigits("1817.759"))
}
```

- [ ] **Step 2: Run the tests to verify they fail because the domain types are absent.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ReadingValidatorTests`

Expected: FAIL with unresolved `ReadingValidator`.

- [ ] **Step 3: Implement the immutable domain model and validator.**

```swift
enum ReadingStatus: String, Codable { case needsReview, positionIdentified, counterRecognized, pendingSync, synced }
struct NormalizedRect: Codable, Equatable { let left: Double; let top: Double; let right: Double; let bottom: Double }
struct DigitProposal: Codable, Equatable { let digits: String; let confidences: [Double]; let uncertainPositions: [Int] }
struct MeterReading: Identifiable, Codable, Equatable {
    let id: UUID; var revision: Int; let meterID: String; let photoID: UUID; let capturedAt: Date
    var window: NormalizedRect?; var proposal: DigitProposal?; var approvedDigits: String?; var status: ReadingStatus
    var modelVersion: String?; var lastSyncError: String?
}
```

`ReadingValidator.approvedDigits(_:)` must accept exactly `[0-9]{5}.[0-9]{3}`, retain the display value, and produce upload digits by stripping leading zeroes from the integer portion while leaving at least one integer digit.

- [ ] **Step 4: Add a SwiftData-backed repository and red-green tests for revision-safe updates.**

```swift
protocol ReadingRepository: Sendable {
    func insert(_ reading: MeterReading) async throws
    func reading(id: UUID) async throws -> MeterReading
    func update(_ reading: MeterReading, expectedRevision: Int) async throws
    func pendingSync() async throws -> [MeterReading]
}
```

The update implementation must increment `revision` only after `expectedRevision` equals the stored revision; mismatches throw `ReadingRepositoryError.staleRevision`.

- [ ] **Step 5: Run focused domain and persistence tests.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ReadingValidatorTests -only-testing:GasPhotoIOSTests/SwiftDataReadingRepositoryTests`

Expected: PASS.

- [ ] **Step 6: Commit the audited reading model.**

```bash
git add GasPhotoIOS/Domain GasPhotoIOS/Data GasPhotoIOSTests/ReadingValidatorTests.swift GasPhotoIOSTests/SwiftDataReadingRepositoryTests.swift
git commit -m "feat: add local reading audit model"
```

### Task 3: Archive original camera images with immutable capture metadata

**Files:**
- Create: `GasPhotoIOS/Photos/PhotoArchive.swift`
- Create: `GasPhotoIOS/Photos/ImageMetadataReader.swift`
- Create: `GasPhotoIOS/Photos/CameraCaptureService.swift`
- Create: `GasPhotoIOSTests/ImageMetadataReaderTests.swift`
- Create: `GasPhotoIOSTests/PhotoArchiveTests.swift`

**Interfaces:**
- Produces: `PhotoReference(id:fileName:sha256:capturedAt:)`, `PhotoArchive.storeOriginal(_:)`, and `CameraCaptureService.capture()`.
- Consumes: `CryptoKit.SHA256`, ImageIO EXIF metadata, and `MeterReading.photoID`.

- [ ] **Step 1: Write a failing metadata fixture test.**

```swift
func testReadsOriginalSubsecondCaptureTimeWithOffset() throws {
    let metadata = try ImageMetadataReader.read(data: fixtureData(named: "meter-exif.jpg"))
    XCTAssertEqual(metadata.capturedAt.ISO8601Format(), "2026-06-18T22:43:42.865+02:00")
}
```

- [ ] **Step 2: Run the fixture test to verify missing reader failure.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ImageMetadataReaderTests`

Expected: FAIL with unresolved `ImageMetadataReader`.

- [ ] **Step 3: Implement ImageIO metadata extraction and archive storage.**

Use `CGImageSourceCopyPropertiesAtIndex`, parse `DateTimeOriginal`, `OffsetTimeOriginal`, and `SubSecTimeOriginal`, and reject data that lacks an offset-aware captured date. Write the exact original bytes below `Application Support/originals/<SHA256>.<extension>` using complete file protection. Return a relative path only; never expose an absolute sandbox path to SwiftData.

```swift
protocol PhotoArchive: Sendable {
    func storeOriginal(_ data: Data, suggestedExtension: String) throws -> PhotoReference
    func url(for photo: PhotoReference) throws -> URL
}
```

- [ ] **Step 4: Implement `AVCapturePhotoOutput` capture without recompressing the returned image data.**

The capture delegate passes `AVCapturePhoto.fileDataRepresentation()` directly to `PhotoArchive.storeOriginal`; photo-library imports use the original resource data when available and are rejected when a capture timestamp cannot be proven.

- [ ] **Step 5: Run the photo tests.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ImageMetadataReaderTests -only-testing:GasPhotoIOSTests/PhotoArchiveTests`

Expected: PASS; the SHA-256 test verifies identical bytes produce the same digest and stored original bytes round-trip unchanged.

- [ ] **Step 6: Commit capture and archive behavior.**

```bash
git add GasPhotoIOS/Photos GasPhotoIOSTests/ImageMetadataReaderTests.swift GasPhotoIOSTests/PhotoArchiveTests.swift
git commit -m "feat: archive original meter photos"
```

### Task 4: Bridge ONNX inference and preserve Mac preprocessing rules

**Files:**
- Create: `GasPhotoIOS/Inference/InferenceService.swift`
- Create: `GasPhotoIOS/Inference/ImagePreprocessor.swift`
- Create: `GasPhotoIOS/Inference/ORTInferenceBridge.h`
- Create: `GasPhotoIOS/Inference/ORTInferenceBridge.mm`
- Create: `GasPhotoIOS/Resources/Models/window-detector-best.onnx`
- Create: `GasPhotoIOS/Resources/Models/digit-classifier-active.onnx`
- Create: `GasPhotoIOSTests/ImagePreprocessorTests.swift`
- Create: `GasPhotoIOSTests/InferenceServiceTests.swift`

**Interfaces:**
- Produces: `InferenceService.propose(imageURL:manualWindow:) async throws -> RecognitionResult`.
- Consumes: `NormalizedRect`, `DigitProposal`, and original image URLs.

- [ ] **Step 1: Write failing preprocessing tests for detector and roller tensor shapes.**

```swift
func testDetectorPreprocessProduces960SquareTensor() throws {
    XCTAssertEqual(try ImagePreprocessor.detectorTensor(from: fixtureImage).shape, [1, 3, 960, 960])
}

func testSplitsTightWindowIntoEightOrderedRollers() throws {
    XCTAssertEqual(try ImagePreprocessor.rollerRects(in: CGSize(width: 800, height: 100)).count, 8)
}
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ImagePreprocessorTests`

Expected: FAIL with unresolved `ImagePreprocessor`.

- [ ] **Step 3: Implement image preprocessing and the Objective-C++ bridge.**

`ImagePreprocessor` must letterbox RGB pixels to NCHW float32 `[1,3,960,960]`, map detector boxes back to original image coordinates, and split the normalized user window as `[round(i*w/8), round((i+1)*w/8))`. Each roller uses the classifier's NCHW float32 `[1,3,128,128]` input. The bridge owns Ort sessions and returns plain Swift-safe arrays of boxes or class probabilities; it must not decide thresholds or statuses.

```swift
struct DetectorCandidate: Equatable { let window: NormalizedRect; let confidence: Double }
struct ClassifierOutput: Equatable { let digit: Int; let confidence: Double }
```

- [ ] **Step 4: Write and run a failing service test for detector ambiguity before implementing decision logic.**

```swift
func testMultipleDetectorCandidatesRequireManualWindow() async throws {
    let a = NormalizedRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3)
    let b = NormalizedRect(left: 0.4, top: 0.5, right: 0.8, bottom: 0.6)
    let service = InferenceService(runtime: FakeRuntime(detector: [.init(window: a, confidence: 0.9), .init(window: b, confidence: 0.8)]))
    let result = try await service.propose(imageURL: fixtureURL, manualWindow: nil)
    XCTAssertNil(result.window)
    XCTAssertNil(result.proposal)
}
```

- [ ] **Step 5: Implement inference decision rules and re-run focused tests.**

Only one detector candidate at or above `0.55` is acceptable. If a manual window exists, bypass detector ambiguity. Invoke the classifier exactly once for each of eight rollers. Populate `uncertainPositions` for confidence below `0.75` at indices `0...4` and below `0.50` at indices `5...7`; retain decimal-review positions for `0.50..<0.75` at indices `5...7`.

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ImagePreprocessorTests -only-testing:GasPhotoIOSTests/InferenceServiceTests`

Expected: PASS.

- [ ] **Step 6: Commit local inference.**

```bash
git add GasPhotoIOS/Inference GasPhotoIOS/Resources/Models GasPhotoIOSTests/ImagePreprocessorTests.swift GasPhotoIOSTests/InferenceServiceTests.swift
git commit -m "feat: run meter models locally on iPhone"
```

### Task 5: Implement approval orchestration and the A review screen

**Files:**
- Create: `GasPhotoIOS/Features/Review/ReviewViewModel.swift`
- Create: `GasPhotoIOS/Features/Review/ReviewView.swift`
- Create: `GasPhotoIOS/Features/Review/WindowEditorView.swift`
- Create: `GasPhotoIOS/Features/Capture/CaptureView.swift`
- Create: `GasPhotoIOSTests/ReviewViewModelTests.swift`

**Interfaces:**
- Consumes: `PhotoArchive`, `InferenceService`, `ReadingRepository`, `ReadingValidator`.
- Produces: `ReviewViewModel.captureAndRecognize()`, `updateWindow(_:)`, `approve(displayDigits:)`, and a disabled approval action for invalid input.

- [ ] **Step 1: Write failing ViewModel tests for the approval gate.**

```swift
func testApproveDoesNotCreatePendingSyncWithoutEightDigits() async throws {
    let model = ReviewViewModel(dependencies: fixtures)
    await model.approve(displayDigits: "1817.759")
    XCTAssertEqual(model.status, .needsReview)
    XCTAssertTrue(fixtures.repository.inserted.isEmpty)
}

func testApproveRecordsManualCorrectionAsPendingSync() async throws {
    let model = ReviewViewModel(dependencies: fixtures)
    await model.approve(displayDigits: "01817.759")
    XCTAssertEqual(fixtures.repository.inserted.single?.status, .pendingSync)
}
```

- [ ] **Step 2: Run the tests to confirm approval orchestration is missing.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ReviewViewModelTests`

Expected: FAIL.

- [ ] **Step 3: Implement the view model with no network dependency.**

`captureAndRecognize()` archives the image first, then records a `needsReview` row and runs inference. `updateWindow(_:)` validates nonzero normalized bounds and re-runs only digit recognition. `approve(displayDigits:)` validates value, saves the proposal/correction and window, writes a training example, and transitions only to `pendingSync`.

- [ ] **Step 4: Build the selected single-screen review UI.**

The view contains full photo preview, green editable window, model confidence label, eight digit field whose last three digits are red, uncertainty warning, immutable capture time, and the explicit `Ellenőriztem, mentés` button. Use Dynamic Type, VoiceOver labels, a 44 pt minimum drag handle, and an image crop editor that never changes original bytes.

- [ ] **Step 5: Re-run ViewModel tests and a simulator build.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/ReviewViewModelTests`

Run: `xcodebuild build -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max'`

Expected: PASS and `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit capture-to-approval flow.**

```bash
git add GasPhotoIOS/Features GasPhotoIOSTests/ReviewViewModelTests.swift
git commit -m "feat: add review and approval flow"
```

### Task 6: Add Keychain OAuth credentials and Home Assistant transport

**Files:**
- Create: `GasPhotoIOS/HomeAssistant/CredentialStore.swift`
- Create: `GasPhotoIOS/HomeAssistant/OAuthCoordinator.swift`
- Create: `GasPhotoIOS/HomeAssistant/HomeAssistantClient.swift`
- Create: `GasPhotoIOSTests/CredentialStoreTests.swift`
- Create: `GasPhotoIOSTests/HomeAssistantClientTests.swift`

**Interfaces:**
- Produces: `CredentialStore`, `OAuthCoordinator.authorize(baseURL:)`, `HomeAssistantClient.checkConnection()`, `import(readings:)`, and `verifiedReadings(ids:)`.
- Consumes: `MeterReading` with `pendingSync` status.

- [ ] **Step 1: Write failing tests for service-response extraction and a missing `gas_photo` service.**

```swift
func testVerifiedReadingsDecodesServiceResponseWrapper() async throws {
    let client = HomeAssistantClient(session: StubURLSession(json: getReadingsJSON))
    let readings = try await client.verifiedReadings(ids: [id])
    XCTAssertEqual(readings[id]?.value, "1817.759")
}

func testCheckConnectionRejectsMissingGasPhotoService() async {
    await XCTAssertThrowsErrorAsync(try await client.checkConnection())
}
```

- [ ] **Step 2: Run the focused tests to verify they fail.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/HomeAssistantClientTests`

Expected: FAIL because no transport exists.

- [ ] **Step 3: Implement Keychain and Authorization Code with PKCE.**

Store `HAOAuthTokens(accessToken:refreshToken:expiresAt:baseURL:)` as one Keychain generic-password item scoped to the app's service identifier. Use `ASWebAuthenticationSession` and a random PKCE verifier/challenge. On refresh, replace the Keychain item atomically. A 401 clears that item and throws `HomeAssistantError.reauthenticationRequired`; no reading rows are deleted.

- [ ] **Step 4: Implement HTTP transport with strict URLs and request verification.**

`HomeAssistantClient` rejects non-HTTPS URLs, credentials in URLs, queries, fragments, redirects, non-JSON responses, and status errors. It adds `Authorization: Bearer <access token>` only inside `URLRequest`. `checkConnection()` reads `/api/config` and `/api/services` and requires the `gas_photo` domain and `import_readings`/`get_readings` services.

- [ ] **Step 5: Implement import and response comparison.**

```swift
protocol HomeAssistantClient: Sendable {
    func checkConnection() async throws -> HomeAssistantConnection
    func importReadings(_ readings: [HomeAssistantReading]) async throws
    func verifiedReadings(ids: [UUID]) async throws -> [UUID: HomeAssistantReading]
}
```

```swift
struct HomeAssistantConnection: Equatable { let version: String; let timeZone: String }
struct HomeAssistantReading: Equatable {
    let id: UUID; let revision: Int; let meterID: String; let value: String; let capturedAt: Date
}
```

POST imports and then reads must include `?return_response`. Compare each ID, revision, meter ID, decimal string after `Decimal` normalization, and ISO-8601 offset timestamp. Any missing or mismatched returned reading throws `HomeAssistantError.verificationFailed`.

- [ ] **Step 6: Run focused credentials and transport tests.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/CredentialStoreTests -only-testing:GasPhotoIOSTests/HomeAssistantClientTests`

Expected: PASS.

- [ ] **Step 7: Commit secure Home Assistant access.**

```bash
git add GasPhotoIOS/HomeAssistant GasPhotoIOSTests/CredentialStoreTests.swift GasPhotoIOSTests/HomeAssistantClientTests.swift
git commit -m "feat: add secure Home Assistant sync transport"
```

### Task 7: Sync the durable queue and expose connection/settings UI

**Files:**
- Create: `GasPhotoIOS/HomeAssistant/SyncCoordinator.swift`
- Create: `GasPhotoIOS/Features/Settings/SettingsViewModel.swift`
- Create: `GasPhotoIOS/Features/Settings/SettingsView.swift`
- Create: `GasPhotoIOS/Features/History/HistoryView.swift`
- Create: `GasPhotoIOSTests/SyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ReadingRepository`, `HomeAssistantClient`, `CredentialStore`.
- Produces: `SyncCoordinator.syncPending() async -> SyncReport`.

- [ ] **Step 1: Write the failing no-partial-sync test.**

```swift
func testVerificationFailureLeavesReadingPendingWithError() async throws {
    let report = await coordinator.syncPending()
    XCTAssertEqual(report.syncedCount, 0)
    XCTAssertEqual(try await repository.reading(id: id).status, .pendingSync)
    XCTAssertEqual(try await repository.reading(id: id).lastSyncError, "A Home Assistant visszaolvasása nem igazolta a leolvasást.")
}
```

- [ ] **Step 2: Run it to verify the coordinator does not exist.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/SyncCoordinatorTests`

Expected: FAIL.

- [ ] **Step 3: Implement queue synchronization.**

`syncPending()` loads at most 100 `pendingSync` rows, imports them, then verifies all rows. Mark a row `synced` only after its individual returned record matches. Preserve pending state and save a Hungarian, token-free error for all failures. Do not use background auto-upload; History provides explicit `Feltöltés a Home Assistantba` action.

- [ ] **Step 4: Implement settings and history views.**

Settings shows connection state, starts OAuth login, allows disconnect (including Keychain deletion), checks `gas_photo`, and never renders tokens. History lists `Ellenőrzésre vár`, `Pozíció azonosítva`, `Számláló felismerve`, `Feltöltésre vár`, and `Szinkronizált` with retry action only for pending rows.

- [ ] **Step 5: Re-run sync tests and simulator UI build.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/SyncCoordinatorTests`

Run: `xcodebuild build -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max'`

Expected: PASS.

- [ ] **Step 6: Commit queue sync UI.**

```bash
git add GasPhotoIOS/HomeAssistant/SyncCoordinator.swift GasPhotoIOS/Features/Settings GasPhotoIOS/Features/History GasPhotoIOSTests/SyncCoordinatorTests.swift
git commit -m "feat: add verified sync queue"
```

### Task 8: Persist training examples, group splits, and model registry

**Files:**
- Create: `GasPhotoIOS/Training/TrainingExample.swift`
- Create: `GasPhotoIOS/Training/TrainingDatasetBuilder.swift`
- Create: `GasPhotoIOS/Training/ModelRegistry.swift`
- Create: `GasPhotoIOSTests/TrainingDatasetBuilderTests.swift`
- Create: `GasPhotoIOSTests/ModelRegistryTests.swift`

**Interfaces:**
- Produces: `TrainingExample`, `DatasetSplit`, `ModelRecord`, and `ModelRegistry`.
- Consumes: approved `MeterReading` and `PhotoReference` records.

- [ ] **Step 1: Write the failing group-split test.**

```swift
func testAllDigitsFromOnePhotoStayInOneDatasetPartition() throws {
    let split = try TrainingDatasetBuilder(seed: 7).makeSplit(examples: fortyExamples)
    let assignments = split.assignments.filter { $0.photoID == photoID }
    XCTAssertEqual(assignments.count, 8)
    XCTAssertEqual(Set(assignments.map(\.partition)).count, 1)
}
```

- [ ] **Step 2: Run the test to verify absent dataset builder failure.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/TrainingDatasetBuilderTests`

Expected: FAIL.

- [ ] **Step 3: Implement labeled examples and deterministic temporal splits.**

On approval with a valid window, write one `TrainingExample` carrying photo ID, revision, normalized window, eight display digits, decision (`approved` or `corrected`), capture date, and model versions. Group split by photo ID and capture-time sequence: 80% train, 10% validation, 10% test, with no group duplicated across partitions. Throw `TrainingDatasetError.insufficientExamples(actual:minimum:)` below 40 unique approved photos.

- [ ] **Step 4: Write and run a failing candidate lifecycle test, then implement model registry.**

```swift
func testCandidateCannotActivateBeforeEvaluationPasses() throws {
    XCTAssertThrowsError(try registry.activate(candidateID))
}
```

`ModelRegistry` persists status (`candidate`, `active`, `rejected`, `superseded`), artifact checksum, dataset fingerprint, evaluation, and file location. Activation moves prior active model to `superseded`; rollback restores the chosen earlier active model and retains audit entries.

- [ ] **Step 5: Run the training persistence tests.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/TrainingDatasetBuilderTests -only-testing:GasPhotoIOSTests/ModelRegistryTests`

Expected: PASS.

- [ ] **Step 6: Commit training metadata.**

```bash
git add GasPhotoIOS/Training/TrainingExample.swift GasPhotoIOS/Training/TrainingDatasetBuilder.swift GasPhotoIOS/Training/ModelRegistry.swift GasPhotoIOSTests/TrainingDatasetBuilderTests.swift GasPhotoIOSTests/ModelRegistryTests.swift
git commit -m "feat: add local training dataset registry"
```

### Task 9: Generate and package reproducible ONNX training artifacts

**Files:**
- Create: `Scripts/prepare_training_artifacts.py`
- Create: `Scripts/requirements-training.txt`
- Create: `TrainingArtifacts/window-detector/manifest.json`
- Create: `TrainingArtifacts/digit-classifier/manifest.json`
- Create: `GasPhotoIOSTests/TrainingArtifactManifestTests.swift`
- Modify: `README.md`

**Interfaces:**
- Produces: versioned training artifact directories containing `training_model.onnx`, `eval_model.onnx`, `optimizer_model.onnx`, `checkpoint/`, and a SHA-256 manifest.
- Consumes: exact bundled ONNX model input/output names and declared trainable final-layer parameter names.

- [ ] **Step 1: Write the failing manifest verification test.**

```swift
func testRejectsArtifactManifestWhenModelDigestDiffers() throws {
    XCTAssertThrowsError(try TrainingArtifactManifest.load(url: tamperedManifestURL))
}
```

- [ ] **Step 2: Run it to confirm the manifest type is absent.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/TrainingArtifactManifestTests`

Expected: FAIL.

- [ ] **Step 3: Implement the Mac-only artifact generator.**

The script must take `--model`, `--output`, `--trainable-parameters`, `--loss cross_entropy`, and `--optimizer adamw`; use `onnxruntime.training.artifacts.generate_artifacts`; calculate SHA-256 for each output; and write a manifest containing model kind, base model digest, expected input shape, output names, artifact digests, and artifact format version. It must fail before writing a manifest if the supplied base model digest does not equal the current bundled model digest.

- [ ] **Step 4: Implement manifest validation in Swift and run the test.**

`TrainingArtifactManifest.load(url:)` verifies all listed relative filenames stay within the artifact directory and each file digest matches. A missing or altered artifact makes on-device training unavailable but does not block inference or manual approval.

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/TrainingArtifactManifestTests`

Expected: PASS.

- [ ] **Step 5: Document the reproducible artifact command and commit.**

Document the exact Python virtual-environment command, source model paths, output artifact layout, and requirement that artifact manifests are regenerated whenever the active ONNX model changes.

```bash
git add Scripts TrainingArtifacts GasPhotoIOSTests/TrainingArtifactManifestTests.swift README.md
git commit -m "feat: package on-device training artifacts"
```

### Task 10: Run on-device candidate training and require evaluation before activation

**Files:**
- Create: `GasPhotoIOS/Training/ORTTrainingBridge.h`
- Create: `GasPhotoIOS/Training/ORTTrainingBridge.mm`
- Create: `GasPhotoIOS/Training/TrainingService.swift`
- Create: `GasPhotoIOS/Training/CandidateEvaluator.swift`
- Create: `GasPhotoIOS/Features/Training/TrainingViewModel.swift`
- Create: `GasPhotoIOS/Features/Training/TrainingView.swift`
- Create: `GasPhotoIOSTests/CandidateEvaluatorTests.swift`
- Create: `GasPhotoIOSTests/TrainingViewModelTests.swift`

**Interfaces:**
- Produces: `TrainingService.start(kind:)`, `TrainingProgress`, `CandidateEvaluator.evaluate(candidate:split:)`, and `ModelRegistry.activate(_:)` guarded by evaluation.
- Consumes: validated artifacts, `TrainingDatasetBuilder`, `ModelRegistry`, and ONNX Runtime Training C APIs.

- [ ] **Step 1: Write the failing evaluation threshold tests.**

```swift
struct EvaluationMetrics { let digitTop1: Double; let highConfidenceMistakes: Int; let windowIoU: Double }
func testCandidateIsRejectedForHighConfidenceMistake() throws {
    let result = CandidateEvaluator.evaluate(metrics: .init(digitTop1: 0.97, highConfidenceMistakes: 1, windowIoU: 0.9), active: .init(digitTop1: 0.95, highConfidenceMistakes: 0, windowIoU: 0.88))
    XCTAssertEqual(result.status, .rejected)
}

func testCandidatePassesWhenItMeetsAllActivationRules() throws {
    let result = CandidateEvaluator.evaluate(metrics: .init(digitTop1: 0.92, highConfidenceMistakes: 0, windowIoU: 0.91), active: .init(digitTop1: 0.90, highConfidenceMistakes: 0, windowIoU: 0.89))
    XCTAssertEqual(result.status, .candidate)
}
```

- [ ] **Step 2: Run the evaluator tests to verify the policy is absent.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/CandidateEvaluatorTests`

Expected: FAIL.

- [ ] **Step 3: Implement candidate evaluation and guarded activation.**

`CandidateEvaluator` accepts only a candidate with `digitTop1 >= 0.90`, zero high-confidence test errors, complete-value and window IoU metrics no lower than active, and a nonempty held-out test partition. `ModelRegistry.activate(_:)` must require a passing evaluation object created for the exact artifact checksum and dataset fingerprint.

- [ ] **Step 4: Implement the Objective-C++ training bridge and a cancellable Swift actor.**

The bridge loads manifest-verified artifacts and checkpoint, feeds only the final-layer parameters selected by the artifact, runs one batch at a time, reports completed epoch/batch/loss, exports a candidate inference model to `Application Support/models/<model-id>/`, and writes it atomically after the final evaluation. `TrainingService` enables battery monitoring and requires `ProcessInfo.processInfo.isLowPowerModeEnabled == false` plus `UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full` before start; cancellation or app termination leaves no active model change.

- [ ] **Step 5: Write and run a failing ViewModel test for the manual-only start gate.**

```swift
func testTrainingIsUnavailableBeforeFortyApprovedPhotos() async {
    await viewModel.refresh()
    XCTAssertEqual(viewModel.primaryAction, .unavailable("40 ellenőrzött fotó szükséges"))
}
```

Build the Training settings screen with separate window/digit cards, example count, train button, foreground progress, candidate metrics, explicit activation, and rollback controls. No training starts automatically.

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/CandidateEvaluatorTests -only-testing:GasPhotoIOSTests/TrainingViewModelTests`

Expected: PASS.

- [ ] **Step 6: Commit on-device training.**

```bash
git add GasPhotoIOS/Training GasPhotoIOS/Features/Training GasPhotoIOSTests/CandidateEvaluatorTests.swift GasPhotoIOSTests/TrainingViewModelTests.swift
git commit -m "feat: train and evaluate local candidate models"
```

### Task 11: Finish integration coverage, privacy documentation, and device verification

**Files:**
- Create: `GasPhotoIOS/Resources/PrivacyInfo.xcprivacy`
- Create: `GasPhotoIOS/Resources/Info.plist`
- Create: `GasPhotoIOSTests/EndToEndReadingFlowTests.swift`
- Create: `docs/verification.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: all public services from Tasks 1–10.
- Produces: reproducible simulator and physical-device verification instructions.

- [ ] **Step 1: Write the end-to-end failing test with fake camera, models, Keychain, and HTTP transport.**

```swift
func testManualCorrectionUploadsOnlyAfterExplicitApprovalAndVerifiedReadback() async throws {
    let sut = makeAppFlow(detector: [.init(window: window, confidence: 0.91)], digits: [0,1,8,1,7,7,5,9])
    try await sut.capture()
    XCTAssertEqual(try await sut.sync().syncedCount, 0)
    try await sut.approve(displayDigits: "01817.759")
    XCTAssertEqual(try await sut.sync().syncedCount, 1)
}
```

- [ ] **Step 2: Run the end-to-end test and fix only uncovered integration seams.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max' -only-testing:GasPhotoIOSTests/EndToEndReadingFlowTests`

Expected: first FAIL at the missing seam, then PASS after the minimal integration implementation.

- [ ] **Step 3: Add camera and photo-library purpose strings plus privacy manifest.**

`NSCameraUsageDescription` must say the camera is used to photograph the gas meter for local reading. `NSPhotoLibraryUsageDescription` must state the app can read a user-selected original meter photo. Privacy manifest declares only accessed required-reason APIs actually used; do not declare collection or tracking because no photo/label/model leaves device.

- [ ] **Step 4: Run the full test suite and simulator build.**

Run: `xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max'`

Run: `xcodebuild build -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS -destination 'platform=iOS Simulator,name=iPhone 14 Pro Max'`

Expected: all tests PASS and `BUILD SUCCEEDED`.

- [ ] **Step 5: Perform physical iPhone 14 Pro Max verification and record results.**

Verify camera permission, original-image timestamp, editable window, detector-only/manual fallback, uncertain digit warning, correction, no pre-approval upload, OAuth login/logout, token absence in log, offline pending queue, service-response verification, candidate training start gate, candidate rejection, activation, and rollback. Add the exact date, OS version, model versions, and pass/fail evidence to `docs/verification.md`; do not include credentials or private image data.

- [ ] **Step 6: Commit final documentation and verification evidence.**

```bash
git add GasPhotoIOS/Resources GasPhotoIOSTests/EndToEndReadingFlowTests.swift docs/verification.md README.md
git commit -m "docs: verify iOS gas meter workflow"
```
