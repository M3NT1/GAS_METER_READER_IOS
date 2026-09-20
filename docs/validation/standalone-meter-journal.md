# Validációs Jelentés: Önálló Mérőóra-napló és Opcionális Home Assistant (Vigavi)

*Dátum: 2026-09-20*  
*Ág: `codex/standalone-meter-journal`*  
*Célplatform: iOS 26.5 Simulator (GasPhoto iPhone 14 Pro Max, ID: 1EA06092-5C2F-4760-BCE2-BA712AE07EF2)*  
*Eszköztár: Xcode 26.6, Swift 6 (Complete Concurrency)*

---

## 1. Vezetői Összefoglaló

A `codex/standalone-meter-journal` feature ágon sikeresen befejeződött a **Vigavi** (**Vi**llany-**Gá**z-**Ví**z) önálló mérőóra-naplózási képességeinek, kézi adatbeviteli és formátumvalidációs felületének, fogyasztásszámításának, valamint az opcionális Home Assistant integrációs kapuinak megvalósítása.

A teljes regressziós tesztcsomag **93 tesztből áll, 0 hibával és 0 kihagyással lefutott (`** TEST SUCCEEDED **`)**.

---

## 2. Megvalósított és Validált Komponensek

### 2.1. Mérőkatalógus és Migráció (SwiftData)
- **Modellek:** `MeterKind` (`electricity`, `gas`, `water`), `RecognitionProfile` (`legacyGas8`, `manual`), `MeterFormat` (érvényes egész és tört jegyek ellenőrzése), `Meter` és `PersistedMeter`.
- **Migráció:** `MeterCatalogBootstrap` biztosítja a meglévő `gas_main` leolvasások idempotens átvételét a katalógusba, adatvesztés nélkül.
- **Tesztelve:** `MeterRepositoryTests` (5 teszt), `MeterFormatTests` (4 teszt).

### 2.2. Kamera és Mérőválasztás
- **Interaktív választó:** A kamera képernyőn (`CaptureView`) közvetlenül kiválasztható az aktív mérőóra, vagy megnyitható a mérőkatalógus (`MeterListView`, `MeterEditorView`).
- **Megváltoztathatatlan pillanatkép:** Fotózáskor a kiválasztott mérő adatai rögzülnek a leolvasáshoz, a későbbi választásváltás nem módosítja a folyamatban lévő leolvasást.
- **Profil szerinti elágazás:** Manuális mérőknél (víz, villany) az ONNX gépi tanulási inferencia teljesen kimarad; a kép mentése és EXIF-időbélyeg ellenőrzése után közvetlenül a kézi jóváhagyó képernyő jelenik meg.
- **Tesztelve:** `CaptureMeterSelectionTests` (3 teszt).

### 2.3. Kézi Jóváhagyás és Értékprogresszió Validáció
- **Kézi bevitel:** `ManualReadingInputView` formátumhoz igazított numerikus bevitelt, magyar tizedesvesszőt és automatikus normalizálást biztosít.
- **Értékprogresszió:** `ReadingProgressionValidator` garantálja, hogy egy adott mérő számlálóállása a korábbi méréshez képest ne csökkenjen, későbbihez képest ne nőjön, és azonos időpontban ne létezzen ütköző érték. A különböző mérők egymástól teljesen függetlenek.
- **Tesztelve:** `ReadingProgressionValidatorTests` (7 teszt), `ReviewViewModelTests` (12 teszt).

### 2.4. Fogyasztási Intervallumok Számítása
- **Szolgáltatás:** `ConsumptionCalculator` a jóváhagyott mérési pontok közötti valós fogyasztási intervallumokat (`ConsumptionInterval`) képezi `Decimal` pontossággal.
- **Adatintegritás:** Csökkenő értékek vagy ütköző időbélyegek esetén jelzi a hibát (nem nyeli el negatív érték abszolútértékével). DST váltásokkor az abszolút időrend megmarad.
- **Felület:** `MeterConsumptionView` összegző kártyával, magyar formázással (pl. `12,450 m³` vagy `350 kWh`), időtartam-kijelzéssel és részletes perióduslistával.
- **Tesztelve:** `ConsumptionCalculatorTests` (7 teszt).

### 2.5. Opcionális Home Assistant Használat és Beépített Útmutató
- **Opcionális kapcsoló:** `HomeAssistantUsageSettings` segítségével a HA kapcsolat új telepítésnél alapértelmezetten ki van kapcsolva. Kikapcsolt állapotban semmilyen hálózati kérés nem indul.
- **Szinkronkapuk:** Csak a szabványos `gas_main` (5+3-as gázóra) tölthető fel a jelenlegi HA integrációba; egyéb mérők `.approvedLocal` ("Helyben mentve") státuszban maradnak. Manuális mérőkből gáz-tanítóminta nem menthető.
- **Beépített útmutató:** `HomeAssistantSetupGuide` és `HomeAssistantSetupGuideView` teljesen offline módon részletezi a telepítést, a HACS-t, a YAML-t, az admin tokent, a kapcsolatteszt határait és az Energy beállítást.
- **Tesztelve:** `HomeAssistantSyncPolicyTests` (3 teszt), `HomeAssistantSetupGuideTests` (7 teszt), `ReadingsHistoryViewModelTests` (6 teszt).

---

## 3. Teszteredmények Részletesen

```
Test Suite 'All tests' passed at 2026-09-20 20:21:39.252.
	 Executed 93 tests, with 0 failures (0 unexpected) in 9.112 (9.311) seconds

Tesztcsoportok:
- AppContainerTests: 1 teszt
- CaptureMeterSelectionTests: 3 teszt
- ConsumptionCalculatorTests: 7 teszt
- HomeAssistantClientTests: 6 teszt
- HomeAssistantResponseDecoderTests: 1 teszt
- HomeAssistantSetupGuideTests: 7 teszt
- HomeAssistantSyncPolicyTests: 3 teszt
- ImageMetadataReaderTests: 1 teszt
- ImagePreprocessorTests: 2 teszt
- InferenceServiceTests: 3 teszt
- KeychainCredentialStoreTests: 1 teszt
- MeterFormatTests: 4 teszt
- MeterRepositoryTests: 5 teszt
- ModelTrainingViewModelTests: 4 teszt
- NormalizedRectTests: 5 teszt
- ONNXRuntimeTests: 4 teszt
- PhotoArchiveTests: 5 teszt
- ReadingProgressionValidatorTests: 7 teszt
- ReadingValidatorTests: 3 teszt
- ReadingsHistoryViewModelTests: 6 teszt
- ReviewViewModelTests: 12 teszt
- SwiftDataReadingRepositoryTests: 2 teszt
- TrainingExampleStoreTests: 1 teszt
```

---

## 4. Határok és Ismert Korlátok

1. **Villany és Vízóra AI felismerés:** Jelenlegi fázisban fotó + kézi bevitel validációval. Nincs rájuk betanított ONNX modell; a gázóra neurális hálózatai nem futnak le rajtuk.
2. **Home Assistant szerveroldali fogadó:** A meglévő `home-assistant-gas-photo` integráció kizárólag a `gas_main` entitást fogadja. A villany- és vízóra szinkronizációhoz külön szerveroldali entitás- és szerződésfejlesztés szükséges.
3. **On-device modelltréning:** A `LocalTrainingService` szimulált állapotban van; a valós mobilos ONNX tréningmotor külön feladat tárgya.
