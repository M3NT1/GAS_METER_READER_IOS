# Changelog

A projekt változásai a [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) irányelvei szerint dokumentálva.

---

## [1.0.0] - 2026-09-12

### ✨ Hozzáadva (Added)

#### 1. 2025/2026 Apple Intelligence Szkennelési Felület és Folyékony Visszajelzés
- **Azonnali zárvillanás és képkimerevítés (`freeze-frame`)**: Megszűnt a „lefagyás” érzés; a fotózás pillanatában a kép azonnal kimerevedik a rögzített fotóra az AI feldolgozás idejére.
- **Színjátszó aura (`iridescent halo`) és neon lézerszkenner (`ScanningReticleOverlay`)**: Forgó, Apple Intelligence stílusú lebegő aura a célkeret körül és fel-le pásztázó lézersugár a felismerési fázisok alatt.
- **Dinamikus Lebegő HUD Kapszula (Dynamic HUD Pill)**: Valós idejű fáziskövetés és vizuális ikonok:
  - `Fotó rögzítése és mentése...`
  - `Számlálókeret keresése AI-val...` (`sparkles.rectangle.stack`)
  - `Számjegyek leolvasása...` (`number.square.fill`)
  - `Sikeres felismerés!` (`checkmark.circle.fill`)
- **Többlépcsős haptikus visszajelzés (`Multi-stage Haptics`)**: Fizikai kattanás expozíciókor (`.medium`), kerettalálatkor (`.light`) és leolvasás végén (`UINotificationFeedbackGenerator - success`).
- **Lézeres görgő-pásztázás az ellenőrző nézetben (`WindowEditorView`)**: Új keret beállításakor a re-analízist horizontális lézerfény kíséri.

#### 2. Kijelzőpontos Finomhangolás és Szubpixel Méretezés (2 pt Magasságig)
- **Layout korlát feloldása**: A számláló címkéjét leválasztottuk a belső keret-konténerről, így a számlálóablak akadálytalanul összehúzható akár **2–5 pt** magasságúra is.
- **Kettős telemetria**: A telemetriai sáv egyszerre jelzi ki az eredeti fotó pixelméretét (`px fotó`) és a képernyő pontméretét (`pt kijelző`).
- **Közvetlen `1 pt`-s léptetés**: Finomhangoló gombok (`-1pt` / `+1pt`) a képernyőpontos állításhoz.
- **Nagyítólupa (`MagnifierLoupeView`)**: Interaktív, lebegő nagyító a sarokpontok pontos ujjmozdulatokkal történő illesztéséhez.
- **Fizikai tárcsás számbeállítók (`RollerDialsView`)**: Tapintható, görgethető tárcsák a felismert számjegyek manuális felülírásához.

#### 3. Home Assistant Integráció és Biztonság
- **Biztonságos Keychain tárolás (`HomeAssistantCredentials`)**: A Home Assistant URL és a Long-Lived Access Token az iOS hardveres kulcstárában tárolódik.
- **Közvetlen REST API szinkronizáció (`URLSessionHomeAssistantClient`)**: Sensor állapotfrissítés `m³` mértékegységgel, időbélyeggel és idempotens küldési sorral.
- **Csökkenés elleni védelem**: A korábbi óraállásnál alacsonyabb érték beküldésének megelőzése és beszédes hibaüzenet megjelenítése.

#### 4. Telefonos Modell-újratanítás (On-Device Training)
- **Helyi Példatár (`SwiftDataTrainingExampleStore`)**: Minden ellenőrzött és jóváhagyott leolvasást a telefon saját helyi tanítóhalmazában tárol.
- **ONNX Runtime Training**: On-device finomhangolási képesség közvetlenül a készüléken, töltés- és akkumulátorfelügyelettel (`TrainingService`).
- **Dedikált tanítási vezérlőpult (`ModelTrainingView`)**: Tanítópéldák számlálója, folyamatjelző és metrikák.

#### 5. Előzmények és SwiftData Adatkezelés
- **Leolvasási előzmények (`ReadingsHistoryView`)**: Keresés, szűrés (szinkronizált, függőben lévő, sikertelen), törlés és manuális újraszinkronizálás.
- **Képmentés (`PhotoArchive`)**: Eredeti fotók SHA-256 lenyomat szerinti archiválása az `Application Support` mappában.

#### 6. Átfogó Tesztelés és Swift 6 Konkurencia
- **48 egységteszt**: Teljes lefedettség az inferenciára, SwiftData repókra, Home Assistant kliensre, koordináta-transzformációkra és nézetmodellekre.
- **Swift 6 Strict Concurrency**: Teljes szálbiztonsági megfelelőség (`SWIFT_STRICT_CONCURRENCY = complete`).

---

## [0.1.0] - 2026-09-11

### ✨ Hozzáadva (Added)
- Kezdeti projekt bootstrap, architektúra és specifikációk.
- YOLOv8 és roller klasszifikációs beágyazott ONNX modellek integrálása.
- Alapvető kamera rögzítés és SwiftData adatbázis konfiguráció.
