# Önálló mérőóra-napló — megvalósítási terv GPT Terra számára

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Ez a kör kizárólag tervezés; implementálni a felhasználó következő fejlesztési utasítása után szabad. Ne indíts automatikusan másik feladatot vagy ügynököt.

**Goal:** HA nélkül használható, villany/gáz/víz mérők szerinti fotós fogyasztási napló, opcionális meglévő gázszinkronnal és beépített HA-telepítési segítséggel.

**Architecture:** A meglévő SwiftData naplót és `meterID` kapcsolatot bővítjük mérőkatalógussal. Megmarad a gáz-ONNX pipeline, keretkorrekció, fotóarchívum, Keychain és HA import/readback; új tiszta formátum-, fogyasztás- és szinkronengedélyezési egységek kapcsolódnak a jelenlegi view modellekhez.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, iOS 26+, jelenlegi CocoaPods/ONNX Runtime függőségek. Új külső csomag nem szükséges.

**Spec:** [Részletes terv és kutatási források](../specs/2026-09-20-standalone-meter-journal-design.md)

## Global Constraints

- Branch: `codex/standalone-meter-journal`; kiinduló main: `1abb4dc`. Sem commit, sem merge nem kerülhet automatikusan a main ágra.
- iOS 26+, fizikai célkészülék iPhone 14 Pro Max.
- Villany/víz elsőként fotó + kézi bevitel; felhasználó által elfogadott döntés.
- A meglévő gáz-OCR, keretszerkesztő, tárcsák, fotóidő-kezelés és HA REST szerződés megmarad.
- Eredeti `capturedAt`, rekordazonosítók, fotóazonosítók és revíziók nem generálhatók újra.
- Nincs automatikus jóváhagyás, feltöltés, interpoláció vagy adatbázis-törléses migráció.
- Csak `gas_main`, 5+3 gázprofil szinkronizálható a jelenlegi HA backenddel.
- Titok kizárólag Keychainben; UserDefaults csak nem titkos kapcsolókhoz.
- A valódi telefonos modelltréning külön fennálló követelmény; a jelenlegi szimulációt nem tekintjük kész implementációnak.
- Fájllistákban **új** = létrehozandó, **módosul** = meglévő elem célzott kiegészítése. A protokollok és típusok lent tervezett interfészek, nem jelenleg létező kód.

## Kiinduló ellenőrzés és munkamód

A 2026-09-20-i állapotmentés: Xcode 26.6 / iOS 26.5 szimulátor, 51 teszt, 0 hiba. A `testDetectorAndClassifierOnRealPhotoIfAvailable` külső helyi fotótól függ; hiányzó fájlnál azonnal visszatér. Ne kezelj egy későbbi zöld futást automatikusan valós fotós bizonyítékként.

Kezdéskor:

```bash
git status --short
git branch --show-current
git log -3 --oneline
xcrun simctl list devices available
```

A végrehajtó ellenőrizze, hogy valóban a feature branch aktív, és őrizze meg a közben megjelent felhasználói módosításokat. Minden feladat előtt célzott failing teszt, utána minimális implementáció és zöld célteszt. A nagyobb változtatások után teljes regresszió. A feladathoz tartozó fájlokat explicit stage-eld; kis commitok maradjanak ezen az ágon.

Tesztparancs (az elérhető szimulátor UUID-jét használd):

```bash
xcodebuild test -workspace GasPhotoIOS.xcworkspace -scheme GasPhotoIOS \
  -destination 'platform=iOS Simulator,id=1EA06092-5C2F-4760-BCE2-BA712AE07EF2' \
  -only-testing:GasPhotoIOSTests/ReadingValidatorTests
```

Az alábbi feladatoknál az `-only-testing:` célját cseréld a megnevezett osztályra; a végső regressziónál hagyd el. Új Swift fájlokat a projektbe is fel kell venni: `ruby Scripts/sync_xcode_sources.rb`, majd ellenőrizni a `GasPhotoIOS.xcodeproj/project.pbxproj` diffjét. Ne generáld újra az egész projektet. `await` eredményt helyi változóba tegyél az XCTest assertion előtt.

## 1. Mérőtípusok és formátumok, a régi gázvalidátor megtartásával

**Fájlok:** új `GasPhotoIOS/Domain/Meter.swift`; módosul `Domain/ReadingValidator.swift`; új `GasPhotoIOSTests/MeterFormatTests.swift`, meglévő `ReadingValidatorTests.swift` regresszióként marad.

**Interfészek:**

```swift
enum MeterKind: String, Codable, CaseIterable, Sendable {
    case electricity, gas, water
    // unit: electricity -> "kWh", gas/water -> "m³"
}
enum RecognitionProfile: String, Codable, Sendable { case legacyGas8, manual }
struct MeterFormat: Codable, Equatable, Sendable {
    let integerDigits: Int // 1...9
    let fractionalDigits: Int // 0...3
}
struct Meter: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    let kind: MeterKind
    let format: MeterFormat
    let recognition: RecognitionProfile
    var isArchived: Bool
}
// Régi ReadingValidator.approvedDigits(_:) marad.
// Új overload:
// static func approvedDigits(_ input: String, format: MeterFormat)
//     throws -> ApprovedReadingValue
```

- [ ] Teszt: a régi 5+3 esetek változatlanok; új overloadnál `12,45`, 6+3 → display `000012.450`, upload `12.450`; 0 tizedesnél `42` → `42`; több elválasztó, túl sok tizedes, mínusz, nem ASCII szám hibát ad.

```swift
func testManualElectricityNormalizesHungarianDecimalInput() throws {
    let result = try ReadingValidator.approvedDigits(
        "12,45", format: MeterFormat(integerDigits: 6, fractionalDigits: 3))
    XCTAssertEqual(result.displayValue, "000012.450")
    XCTAssertEqual(result.uploadValue, "12.450")
}
```

- [ ] Futtasd a `MeterFormatTests` osztályt; az új interfész hiánya miatt kezdetben hibáznia kell.
- [ ] Készítsd el a fenti típusokat és az overloadot. Ne írd át az `ImagePreprocessor`, `ONNXRuntime` vagy `RollerDialsView` algoritmusát. A formátumtartomány ellenőrzése a mérő létrehozásánál és a parserben is érvényesüljön; hibánál ne legyen kerekítés.
- [ ] Futtasd a `MeterFormatTests` és `ReadingValidatorTests` tesztjeit; commit: `feat: add meter categories and reading formats`.

## 2. Mérőkatalógus és adatmegőrző SwiftData-bővítés

**Fájlok:** új `Data/SwiftDataMeterRepository.swift`, `Data/InMemoryMeterRepository.swift`, `Data/MeterCatalogBootstrap.swift`; szükség esetén új `Data/MeterSchemaMigration.swift`; módosul `App/AppContainer.swift`; új `GasPhotoIOSTests/MeterMigrationTests.swift`, `MeterRepositoryTests.swift`.

**Interfészek:**

```swift
@MainActor protocol MeterRepository: AnyObject {
    func allMeters() async throws -> [Meter]
    func meter(id: String) async throws -> Meter
    func save(_ meter: Meter) async throws
}
// MeterCatalogBootstrap.run(readings: [MeterReading],
//                           meters: any MeterRepository) async throws
```

`PersistedMeter` lapos mezőkkel tárol: id, name, kindRawValue, integerDigits, fractionalDigits, recognitionRawValue, isArchived. Ne vezesd át a teljes régi leolvasási modellt új kapcsolathálóra.

- [ ] Hozz létre régi sémás lemezes fixture-t: `gas_main` leolvasások különféle státuszokkal, pontos idővel, revízióval és tréningmintával. A teszt a régi container bezárása után az új sémával nyissa meg ugyanazt a store-t. Ne in-memory migrációval helyettesítsd.
- [ ] Ellenőrzések: rekordok/minták száma és összes értéke változatlan; katalógusban egy `gas_main` jön létre; a bootstrap második futása nem duplikál; ismeretlen régi ID megmarad külön archivált mérőként. A fixture fotóazonosítói továbbra is ugyanarra az archívumra mutatnak.
- [ ] Futtasd a failing `MeterMigrationTests`-et. Válaszd az additív séma legkisebb működő migrációját; ha verziózott séma kell, a régi modellek pontos checksumát a fixture-rel igazold. Sikertelen megnyitáskor megőrzés és érthető hiba, soha üres store-létrehozás.
- [ ] Implementáld a fenti repository-kat és idempotens bootstrapet; `AppContainer` új függőségként adja át a katalógust. Az archívum helyét és az eredeti reading repository API-ját őrizd meg.
- [ ] Teszteld a `MeterMigrationTests`, `MeterRepositoryTests`, `SwiftDataReadingRepositoryTests`, `TrainingExampleStoreTests`, `AppContainerTests` osztályokat; commit: `feat: persist meter catalog without replacing existing readings`.

## 3. Önálló mentés és közös HA-engedélyezés

**Fájlok:** módosul `Domain/Reading.swift`, `Features/Review/ReviewViewModel.swift`, `Features/History/ReadingsHistoryViewModel.swift`, `HomeAssistant/HomeAssistantSettingsView.swift`, `App/AppContainer.swift`; új `HomeAssistant/HomeAssistantUsageSettings.swift`, `HomeAssistant/HomeAssistantSyncPolicy.swift`; új `GasPhotoIOSTests/HomeAssistantSyncPolicyTests.swift`; módosul review/history teszt és minden `ReadingStatus` switch.

**Interfészek:**

```swift
// ReadingStatus új esete: approvedLocal; régi raw value-k változatlanok.
@MainActor protocol HomeAssistantUsageSettings: AnyObject {
    var isEnabled: Bool { get set }
    func initializeIfNeeded(hasCredentials: Bool)
}
enum HomeAssistantSyncPolicy {
    static func supports(_ meter: Meter) -> Bool
    static func mayStartRequest(enabled: Bool, meter: Meter) -> Bool
}
```

`supports`: pontosan `gas_main`, `.gas`, 5+3, `.legacyGas8`. A jóváhagyást és a hitelesítő adatok meglétét a meglévő view model ellenőrzi, de a hálózati szabály ugyanaz mindenhol. A kapcsolatteszt a globális `isEnabled` értéket ellenőrzi (nem mérőhöz kötött).

- [ ] Teszteld, hogy az új felhasználónál a HA ki van kapcsolva; korábbi credentials mellett csak első alkalommal kapcsol be; explicit kikapcsolás app-újraindítás után is megmarad.
- [ ] Review teszt fake klienssel: kikapcsolva approve → `approvedLocal`, 0 request; explicit sync is 0; bekapcsolt `gas_main` approve → `pendingSync`, továbbra is 0 request; explicit sync → 1 importfolyamat és csak ellenőrzött válasz után `synced`.
- [ ] Ugyanezt ellenőrizd history egyedi/tömeges küldésnél, kézzel visszahívott actionnel is; víz/villany/új gáz ID soha nem jut a klienshez. A ki kapcsolás minden batch-elem előtt újra ellenőrzendő. Már elindult kérés eredménye menthető.
- [ ] Futtasd a failing célteszteket, majd a fenti interfészekkel egészítsd ki az állapotgépet és minden hívási pontot. A régi `pendingSync`/`synced` rekordokat ne migráld át, a feltöltési payload/decoder marad.
- [ ] Tárolási hiba/revízióütközés tesztek: ne jelenjen meg sikeres mentés/szinkron, ha a repository nem mentett. A meglévő `try?` hibanyelést csak az érintett mentési ágban javítsd, és kizárólag regressziós teszttel.
- [ ] Céltesztek + `HomeAssistantClientTests`/`HomeAssistantResponseDecoderTests`; commit: `feat: make Home Assistant optional across all sync entry points`.

## 4. Mérőválasztás a kamera- és importfolyamatban

**Fájlok:** új `Features/Meters/MeterListView.swift`, `MeterEditorView.swift`; módosul `Features/Settings/AppSettingsView.swift`, `Features/Capture/CaptureView.swift`, `CaptureViewModel.swift`, `App/RootView.swift`; új `GasPhotoIOSTests/CaptureMeterSelectionTests.swift`.

**Interfész:** `CaptureViewModel.selectedMeterID: String?`; induláskor katalógusfeloldás és változtathatatlan `Meter` pillanatkép az adott capture/import feladathoz. A review inicializálója a pillanatképet kapja, nem az élő selectiont.

- [ ] Failing teszt: A mérővel induló fotó, feldolgozás közben B kiválasztása → az elkészült reading és review továbbra is A. Ugyanez könyvtári importra. Ismeretlen/archivált ID-val új capture nem indul.
- [ ] Mérőfelvétel: név kötelező; kategória és formátum érvényes; profilt csak kompatibilis gázformátum enged. Az első leolvasás után a kategória/formátum/profil szerkesztése tiltott. Archiválás megőrzi a naplót; ne legyen cascade delete.
- [ ] Mindkét fix `meterID: "gas_main"` helyett a pillanatkép ID-ját add át. Üres katalógusnál legyen létrehozási út, és ne bukjon el az app hiányzó HA miatt.
- [ ] Manual profilnál hagyd ki az inferenciát, de a meglévő kamera, archiválás, EXIF-validáció és review átadás marad. A gas profil ugyanazt a pipeline-t hívja, mint korábban.
- [ ] Futtasd `CaptureMeterSelectionTests`, `ImageMetadataReaderTests`, `PhotoArchiveTests`, `InferenceServiceTests`; commit: `feat: select a concrete meter before photo capture`.

## 5. Kézi review és mérőnkénti értékellenőrzés

**Fájlok:** új `Features/Review/ManualReadingInputView.swift`, `Domain/ReadingProgressionValidator.swift`; módosul `Features/Review/ReviewView.swift`, `ReviewViewModel.swift`, `Features/History/ReadingsHistoryViewModel.swift`; új `GasPhotoIOSTests/ReadingProgressionValidatorTests.swift`; bővül `ReviewViewModelTests.swift`, `ReadingsHistoryViewModelTests.swift`.

**Interfész:**

```swift
enum ReadingProgressionValidator {
    static func validate(candidate: MeterReading, approved: ApprovedReadingValue,
                         meter: Meter, allReadings: [MeterReading]) throws
}
```

A függvény előbb `meter.id` szerint szűr, a jelölt saját ID-ját kizárja; jóváhagyott előző/következő pontot néz `capturedAt` szerint. Azonos időpontra másik rekord esetén duplikált/ütköző idő hibát ad. Formátum szerinti canonical szöveget `Decimal` értékké alakít; sem a pozíció, sem az egység nem globális állandó.

- [ ] Failing tesztek: két külön vízóra 100 és 5 m³ állása nem akadályozza egymást; időben köztes 15 elfogadható 10 és 20 között; 25 vagy 5 hibás; azonos időpont ütközik; azonos érték későbbi időpontban megengedett.
- [ ] A review fejlécében mérőnév/egység, manual profilon fotó és `decimalPad` mező. Gas profilon meglévő keret/tárcsák. Mentésgomb és helyi sikerállapot használható HA nélkül.
- [ ] Add meg a formátumfüggő validálást a meglévő jóváhagyási folyamatnak; köztes leolvasás ellenőrzéséhez használd a tiszta validátort. Ne módosítsd a fotó eredeti idejét.
- [ ] Mind a review, mind az előzmény kézi tanítóminta-regisztrációja utasítsa el a `manual` profilt. Ellenőrizd fake inference/training store-ral: víz/villany mentés 0 inferencia és 0 gáztréningminta, gázút megőrzi az eddigi példagyűjtést.
- [ ] Céltesztek, majd gas review regresszió; commit: `feat: review manual utility readings without changing gas recognition`.

## 6. Valós mérési intervallumok és fogyasztási nézet

**Fájlok:** új `Domain/ConsumptionCalculator.swift`, `Features/History/MeterConsumptionView.swift`; módosul `Features/History/ReadingsHistoryView.swift`, `ReadingsHistoryViewModel.swift`; új `GasPhotoIOSTests/ConsumptionCalculatorTests.swift`.

**Interfészek:**

```swift
struct ConsumptionInterval: Equatable, Sendable {
    let fromReadingID: UUID
    let toReadingID: UUID
    let start: Date
    let end: Date
    let amount: Decimal
}
enum ConsumptionCalculator {
    static func intervals(readings: [MeterReading], meter: Meter)
        throws -> [ConsumptionInterval]
}
```

- [ ] Failing tesztadatok: ugyanazon mérő időrendben 100.000, 102.350, 103.000 → 2.350 és 0.650; kevert másik mérő és nem jóváhagyott sor nem számít bele. Üres/egyetlen jóváhagyott sor → üres intervallumlista.
- [ ] Köztes beszúrás 101.000 → 1.000 és 1.350; köztes törlés után az eredeti 2.350 tér vissza. Csökkenés/azonos idejű külön rekord → jelzett adathiba; nem nyeljük el negatív érték abszolútértékével. DST-s időpár abszolút sorrendben marad.
- [ ] Implementáld a tiszta kalkulátort és a mérőszűrőt. Megjelenítés `Decimal`-ból, a mérő tizedespontosságával, magyar lokalizációval. Az összesítés az intervallumok összege és a tényleges start/end időtartomány, első alapállásnál „—”.
- [ ] Az új intervallumlista/összesítés a meglévő előzményekből elérhető, nem új alkalmazásnavigáció. Leolvasás törlése és reload után újraszámol; külön kategóriák összesítése nincs.
- [ ] `ConsumptionCalculatorTests`, history regresszió, kézi üres/egy/több mérős UI-próba; commit: `feat: show consumption between verified meter readings`.

## 7. Beállítások és offline HA-telepítési útmutató

**Fájlok:** új `Features/Settings/HomeAssistantSetupGuide.swift`, `HomeAssistantSetupGuideView.swift`; módosul `Features/Settings/AppSettingsView.swift`, `HomeAssistant/HomeAssistantSettingsView.swift`; új `GasPhotoIOSTests/HomeAssistantSetupGuideTests.swift`; új `docs/home-assistant-setup.md`.

**Interfész:** helyi, típusos szekciólista cím/szöveg/HTTPS linkekkel, `lastVerified = "2026-09-20"`. A SwiftUI view ezt jeleníti meg. A teljes felhasználói szöveg alapja a specifikáció „HA-útmutató” fejezete; a Markdown változat ugyanennek a karbantartható párja.

- [ ] Teszt: a guide tartalmazza a pontos integráció-repó URL-t, HACS és kézi utat, YAML-t, admin token követelményt, kapcsolatteszt korlátját, `gas_photo:gas_main` azonosítót; minden link abszolút HTTPS; nem tartalmaz hitelesítő adatot vagy dinamikusan beillesztett tokent.
- [ ] UI: HA kapcsoló, alatta bármikor elérhető „Telepítési útmutató”. Kikapcsolva nincs tokenkérés vagy automatikus kapcsolatteszt; bekapcsolva a meglévő credential view nyílik. Váltás azonnal frissítse a kamera/review/history műveleteket is.
- [ ] A specifikáció útmutatóját implementáld helyi adatként; új WebView és távoli tartalomletöltés nem kell. A külső linkeket `Link` nyissa meg, ne tartalmazzanak tokent.
- [ ] Javítsd az érintett beállítási szövegek tényszerűségét: a fotóarchívum nem Keychain, HA-feltöltéskor adat távozik, a tanítás szimulációs státusza ne legyen működő tréningként feltüntetve. A tanítás motorját ne építsd át ebben a feladatban.
- [ ] Guide teszt + repülő módos UI-próba; linkmegnyitás online és hibaüzenetek token nélküli ellenőrzése; commit: `feat: document optional Home Assistant setup inside settings`.

## 8. Készülékes regresszió, migrációs próba és átadás

**Fájlok:** módosul `README.md`, `CHANGELOG.md`; új `docs/validation/standalone-meter-journal.md` a tényleges eredményekkel. Ne írj sikeres státuszt még le nem futott próbához.

- [ ] Futtasd a teljes XCTest csomagot `-only-testing` nélkül, új xcresult útvonallal. Rögzítsd a verziókat, tesztszámot, hibákat, kihagyásokat. A korábbi 51 teszt nem feltétlen marad pontosan 51 az új lefedettség után.
- [ ] Régi store teljes másolatával migrációs próba: rekordok, fotókapcsolatok, tréningminták, ID-k, időpontok és HA-állapotok összehasonlítása. Újraindítás kétszer, megszakított bootstrap újrapróbálása, visszaállítás zárt store-mentésből.
- [ ] Fizikai iPhone 14 Pro Max, iOS 26+: HA nélkül három kategória, két azonos kategóriájú mérő, kamera/import, manuális érték, újraindítás és fogyasztás. Gas OCR valódi referenciafotóval; a kamera/keret/tárcsák interakciója is maradjon használható.
- [ ] HA fake request-számlálóval: kikapcsolva 0 kérés minden műveletnél. Valós HA-val csak a felhasználó által ellenőrzött gázállást küldd; mesterséges tesztállást ne írj az éles ledgerbe. Import/readback, duplikált retry, offline/401 hiba és helyi adatmegőrzés ellenőrzése.
- [ ] Dokumentáld a támogatott HA-verziót a tényleges próbából; a jelenlegi integráció manifestje alapján ne találj ki minimumverziót. Az Energy megjelenítés és a ledgerbe mentés külön ellenőrzés.
- [ ] `git diff --check`, változások felülvizsgálata: nincs új ONNX modell/runtime, nincs HA szerverátírás, nincs titok vagy privát mintafotó stage-elve. README: önálló funkciók, víz/villany kézi jelleg, gáz-only HA korlát, útmutatólink, valódi validálási állapot.
- [ ] Commit és push kizárólag a feature branchre: `docs: record standalone journal validation and limitations`. A main merge külön felhasználói döntés.

## Későbbi, külön scope

- Általános villany/víz OCR csak tényleges mintaképek és mérőtípusonkénti értékelés után.
- Több mérő és kategória HA fogadása külön backend tervet, egység/statistic-ID szerződést és migrációt igényel; nem kliensoldali címkeváltás.
- CSV/export, tarifák, költségszámítás, iCloud szinkron és automatikus meter-reset támogatás nem szükséges ehhez az első változathoz.
- Valódi telefonos modelltréning befejezése külön meglévő feladat, a minták kompatibilitását ez a feature megőrzi.

## Következő körben átadható utasítás

> A `codex/standalone-meter-journal` feature branchen dolgozz GPT Terrával. Először olvasd el ezt a tervet és a kapcsolt specifikációt. Az 1–2. feladattal indulj: formátumok és adatmegőrző mérőkatalógus. A meglévő gázfelismerést, fotóidőket és HA-szinkront ne írd újra. Villany/víz elsőként fotó + kézi bevitel. Célzott tesztekkel igazold a migrációt, majd kis commitokban haladj a terv szerint. A main ágat ne módosítsd és ne merge-ölj automatikusan.
