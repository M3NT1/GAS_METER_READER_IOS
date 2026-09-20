# GasPhotoIOS — Helyi Mesterséges Intelligenciás Gázóra-leolvasó iOS Alkalmazás

[![Platform](https://img.shields.io/badge/Platform-iOS%2026%2B-blue.svg?style=flat-square&logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0%20Complete%20Concurrency-orange.svg?style=flat-square&logo=swift)](https://swift.org/)
[![Runtime](https://img.shields.io/badge/Inference-ONNX%20Runtime%20Mobile-green.svg?style=flat-square)](https://onnxruntime.ai/)
[![Home Assistant Integration](https://img.shields.io/badge/Home%20Assistant-home--assistant--gas--photo-41BDF5.svg?style=flat-square&logo=home-assistant)](https://github.com/M3NT1/home-assistant-gas-photo)

A **GasPhotoIOS** egy modern, natív iOS alkalmazás Sacofgas G4 és kompatibilis gázórák automatikus leolvasására és Home Assistant integrációjára. Az alkalmazás **100%-ban helyben (On-Device)**, internetkapcsolat és külső felhőszolgáltatás nélkül, beágyazott neurális hálózatokkal ismeri fel a számlálókeretet és a 8 darab analóg görgő számjegyeit (5 fekete egész + 3 piros tizedes).

---

## 🔗 Kapcsolódó Home Assistant Integráció (Kötelező a szinkronizációhoz!)

> [!IMPORTANT]
> A leolvasott adatok Home Assistantba történő beküldéséhez és az Energy Dashboard órás statisztikáihoz a Home Assistant szervereden futnia kell a szerveroldali egyedi integrációnak:
>
> 🏠 **[home-assistant-gas-photo](https://github.com/M3NT1/home-assistant-gas-photo)**
>
> A két tároló együtt biztosítja a Home Assistantba szinkronizáló rendszert: az iPhone elvégzi a helyi AI leolvasást, a Home Assistant integráció pedig fogadja az adatot, vezeti a megbízható naplót (`ledger`), és ellátja adatokkal az Energia panelt.

---

## 🌟 Fő Funkciók

### 1. 🧠 Teljesen Helyi Gépi Látás és Neurális Hálózatok
- **Számlálókeret-kereső (YOLOv8)**: Automatikusan lokalizálja a mérő számlálóablakát a 12 MP / 4K kamerafotón.
- **Számjegy-osztályozó (8 görgős konvolúciós háló)**: Egyenként értékeli a felismert számláló 8 darab görgőjét (0–9 számjegyek + bizonytalansági konfidenciaérték).
- **Adatvédelem és Sebesség**: A felismerés a készüléken fut. A fotóarchívum és a helyi napló az alkalmazás tárhelyén van; a felhasználó által indított HA-feltöltés az óraállást és a kapcsolódó metaadatokat küldi el. A Fotók könyvtárba mentett képekre a rendszer iCloud-beállításai érvényesek.

### 2. ✨ 2025/2026 Apple Intelligence Scanner Élmény
- **Zárvillanás & Kimerevített Előnézet (Freeze-Frame)**: A fotó exponálásakor a kép azonnal kimerevedik, elkerülve a „lefagyott az app” érzést az AI futás közben.
- **Színjátszó Aura (Iridescent Halo)**: Folyamatosan pulzáló, Apple Intelligence stílusú lebegő aura a célkeret körül.
- **Neon Lézerszkenner**: Dinamikus pásztázó lézersugár a keret belsejében a felismerési fázisok alatt.
- **Dinamikus Lebegő HUD Kapszula**: Valós idejű fáziskijelzés (`Fotó mentése` ➔ `Keret keresése AI-val` ➔ `Számjegyek leolvasása` ➔ `Sikeres felismerés`).
- **Többlépcsős Haptikus Rezgés**: Külön fizikai kattanás expozíciókor, kerettalálatkor és leolvasáskor.

### 3. 🎛️ Szubpixel és Kijelzőpontos Finomhangolás
- **Érintéses Keretmozgatás & Méretezés**: A számlálóablak kézzel áthelyezhető és akár **2–5 pt (4–10 px)** magasságúra is összehúzható, így a számsor feletti/alatti zavaró feliratok teljesen kizárhatók.
- **Interaktív Nagyítólupa (Magnifier Loupe)**: A sarkok húzásakor automatikusan megjelenő lebegő nagyító a hajszálpontos illesztéshez.
- **Görgős Számválasztók (Roller Dials)**: A felismert számjegyek a fizikai görgőkhöz hasonló tapintható tárcsákkal kézzel is felülírhatók.
- **Kettős Telemetria**: Külön mutatja az eredeti fotó pixelméretét (`px fotó`) és a képernyő pontméretét (`pt kijelző`).

### 4. 🏠 Home Assistant Szinkronizáció
- **Közvetlen REST API Szinkron**: Az ellenőrzött leolvasás egyetlen gombnyomással szinkronizálható a [home-assistant-gas-photo](https://github.com/M3NT1/home-assistant-gas-photo) integrációval.
- **Külön helyi jóváhagyás és feltöltés**: A jóváhagyás helyben ment; a HA-feltöltés külön művelet.
- **Stabil rekordazonosító és revízió**: A leolvasás UUID-jéből képzett azonosítóval küld, majd visszaolvassa és ellenőrzi a szerveren tárolt rekordot.
- **Csökkenés Elleni Védelem**: Nem engedi beküldeni a korábbi óraállásnál kisebb értéket.
- **Biztonságos Keychain Tárolás**: A Home Assistant URL és a Long-Lived Access Token az iOS Keychainben tárolódik.

### 5. Helyi tanítópéldák és tanítási felület
- A jóváhagyott/javított, kerettel rendelkező gázleolvasások helyi tanítópéldaként tárolhatók.
- A tanítási vezérlőpult, előfeltétel-ellenőrzés és a csomagolt ONNX Training erőforrások rendelkezésre állnak.
- **Korlát:** a jelenlegi `LocalTrainingService` szimulált epochokat és metrikákat ad; az aktiválás állapotmetaadatot ment. Valódi `ORTTrainingSession`, mért modellértékelés és az inferenciában használt modell cseréje még nincs bekötve. A telefonos modelltréning ezért nem tekinthető kész funkciónak.

### 6. 📊 Önálló Mérőóra-napló és Fogyasztási Intervallumok (Vigavi)
- **Több mérőkategória**: Villany (`kWh`), gáz (`m³`) és víz (`m³`) mérők kezelése egyetlen felületen.
- **Mérőkatalógus**: Tetszőleges számú mérőóra felvétele, testreszabható számláló-formátum (egész és tört jegyek száma), archiválási lehetőség.
- **Kézi jóváhagyás**: Víz- és villanyórákhoz fotó + formátumhoz igazított kézi bevitel magyar tizedesvessző-támogatással.
- **Értékprogresszió-védelem**: Nem engedi a számláló visszafelé járását vagy azonos időpontú ütközéseket.
- **Fogyasztásszámítás**: Valós mérési intervallumok és összegzett időszakos fogyasztás megjelenítése mérőnként (`MeterConsumptionView`).
- **Opcionális Home Assistant kapcsolat**: Új telepítésnél alapértelmezetten kikapcsolt; offline módban nulla hálózati kérés.
- **Beépített telepítési útmutató**: Teljesen offline elérhető lépésről-lépésre útmutató a beállításokban és a [docs/home-assistant-setup.md](docs/home-assistant-setup.md) fájlban.

---

## 🏗️ Architektúra és Mappa-struktúra

```
GasPhotoIOS/
├── App/
│   ├── GasPhotoIOSApp.swift          # Alkalmazás belépési pont
│   ├── AppContainer.swift             # Dependency Injection & Service Factory
│   └── RootView.swift                 # Kamera és ellenőrzés közti navigáció
├── Domain/
│   ├── Meter.swift                    # Mérő modell, kategóriák, formátumok
│   ├── Reading.swift                  # Leolvasás modell (állapotok, normalizált érték)
│   ├── ReadingValidator.swift         # Formátum és számszaki validáció
│   ├── ReadingProgressionValidator.swift # Mérőnkénti időbeli növekedés validáció
│   ├── ConsumptionCalculator.swift    # Fogyasztási intervallumok és összegzés
│   └── ModelTrainingDomain.swift      # Tanítási állapotgépek és konfigurációk
├── Features/
│   ├── Capture/                       # Élő kamera nézet, mérőválasztó, Apple Intelligence szkenner HUD
│   ├── Review/                        # Leolvasás-ellenőrző (gáz tárcsák vagy kézi numerikus bevitel)
│   ├── History/                       # SwiftData leolvasási napló, szűrés, fogyasztási nézet
│   ├── Meters/                        # Mérőkatalógus (lista és szerkesztő)
│   ├── Training/                      # On-device modell tanítás vezérlőpult
│   └── Settings/                      # Beállítások, HA kapcsolat és offline útmutató
├── HomeAssistant/
│   ├── HomeAssistantClient.swift      # REST API szinkronizáció
│   ├── HomeAssistantSyncPolicy.swift  # Feltöltési kapuk és szabályok
│   └── HomeAssistantUsageSettings.swift # Opcionális használati kapcsoló
├── Inference/
│   ├── InferenceService.swift         # YOLOv8 és roller klasszifikáció orchestrator
│   ├── ONNXRuntime.swift              # Swift burkoló az ONNX futtatókörnyezethez
│   ├── ORTInferenceBridge.[h|mm]      # C++ / Objective-C++ híd az onnxruntime-c könyvtárhoz
│   └── ModelBundle.swift              # Beágyazott .onnx modellek feloldása
├── Data/
│   ├── SwiftDataMeterRepository.swift
│   ├── SwiftDataReadingRepository.swift
│   ├── SwiftDataTrainingExampleStore.swift
│   └── MeterCatalogBootstrap.swift
└── Photos/
    ├── CameraCaptureService.swift     # AVFoundation 4K fotórögzítés
    ├── ImageMetadataReader.swift      # EXIF időbélyeg és al-másodperc felolvasás
    └── PhotoArchive.swift             # SHA-256 hash alapú helyi képmentés
```

---

## 📋 Validációs Állapot

A részletes teszteredményeket és határvonalakat a [docs/validation/standalone-meter-journal.md](docs/validation/standalone-meter-journal.md) tartalmazza (93 teszt, 0 hiba).

---

## 🚀 Fejlesztői Környezet és Beállítás

### Előfeltételek
- **Az Xcode 26 által támogatott macOS-verzió**
- **Xcode 26+**, iOS 26+ SDK és futtatókörnyezet
- **CocoaPods** (`brew install cocoapods` vagy `gem install cocoapods`)

### Telepítés és Indítás

1. Klónozd a tárolót:
   ```bash
   git clone https://github.com/M3NT1/GAS_METER_READER_IOS.git
   cd GAS_METER_READER_IOS
   ```

2. Telepítsd a CocoaPods függőségeket (`onnxruntime-training-objc` 1.19.2, a Podfile.lock szerint):
   ```bash
   pod install
   ```

3. Nyisd meg a generált Xcode Workspace-t:
   ```bash
   open GasPhotoIOS.xcworkspace
   ```

4. Válaszd ki a célkészüléket (pl. a csatlakoztatott iPhone-odat vagy egy iOS Szimulátort), majd nyomj **⌘R** gombot a futtatáshoz.

---

## 🧪 Automatizált Tesztelés

A projekt szigorú, Swift 6 szálbiztonsági (`SWIFT_STRICT_CONCURRENCY = complete`) szabályoknak megfelelő egységtesztekkel van lefedve.

Először válassz elérhető iOS 26+ szimulátort az `xcrun simctl list devices available` paranccsal. A teljes tesztcsomag:
```bash
xcodebuild test \
  -workspace GasPhotoIOS.xcworkspace \
  -scheme GasPhotoIOS \
  -destination "platform=iOS Simulator,id=<SIMULATOR_UDID>"
```

**Teszteredmények:**
- A korábbi 48/48 eredmény történeti adat; az aktuális ellenőrzés eredménye a [CHANGELOG](CHANGELOG.md) 2026-09-20-i bejegyzésében szerepel.
- A valódi fotós ONNX-teszt helyi, repón kívüli mintaképet használ, és hiányzó fájlnál visszatér; a zöld tesztszám önmagában nem bizonyítja ennek a mintának a kiértékelését.
- A szimulátorteszt nem helyettesíti a fizikai iPhone-os kamera- és élő HA-ellenőrzést.
- Lefedett területek:
  - Inferencia pipeline és aszinkron fázisjelentés (`InferenceServiceTests`)
  - ONNX Runtime integráció és görgő-kiértékelés (`ONNXRuntimeTests`)
  - SwiftData perzisztencia és tranzakciók (`SwiftDataReadingRepositoryTests`)
  - Home Assistant REST API kommunikáció és hibakezelés (`HomeAssistantClientTests`)
  - Számlálókeret normalizálás és koordináta-transzformációk (`NormalizedRectTests`)
  - Leolvasás-érvényesítés és felülbírálati szabályok (`ReadingValidatorTests`, `ReviewViewModelTests`)

---

## 📄 Licenc

Ez a projekt nyílt forráskódú, az [MIT Licenc](LICENSE) feltételei szerint használható és módosítható.
