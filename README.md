# GasPhotoIOS — Helyi Mesterséges Intelligenciás Gázóra-leolvasó iOS Alkalmazás

[![Platform](https://img.shields.io/badge/Platform-iOS%2018%2B%20%2F%20iOS%2026-blue.svg?style=flat-square&logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0%20Complete%20Concurrency-orange.svg?style=flat-square&logo=swift)](https://swift.org/)
[![Runtime](https://img.shields.io/badge/Inference-ONNX%20Runtime%20Mobile-green.svg?style=flat-square)](https://onnxruntime.ai/)
[![Home Assistant](https://img.shields.io/badge/Integration-Home%20Assistant-41BDF5.svg?style=flat-square&logo=home-assistant)](https://www.home-assistant.io/)
[![Tests](https://img.shields.io/badge/Tests-48%2F48%20Passed-brightgreen.svg?style=flat-square)]()

A **GasPhotoIOS** egy modern, natív iOS alkalmazás Sacofgas G4 és kompatibilis gázórák automatikus leolvasására és Home Assistant integrációjára. Az alkalmazás **100%-ban helyben (On-Device)**, internetkapcsolat és külső felhőszolgáltatás nélkül, beágyazott neurális hálózatokkal ismeri fel a számlálókeretet és a 8 darab analóg görgő számjegyeit (5 fekete egész + 3 piros tizedes).

---

## 🌟 Fő Funkciók

### 1. 🧠 Teljesen Helyi Gépi Látás és Neurális Hálózatok
- **Számlálókeret-kereső (YOLOv8)**: Automatikusan lokalizálja a mérő számlálóablakát a 12 MP / 4K kamerafotón.
- **Számjegy-osztályozó (8 görgős konvolúciós háló)**: Egyenként értékeli a felismert számláló 8 darab görgőjét (0–9 számjegyek + bizonytalansági konfidenciaérték).
- **Adatvédelem és Sebesség**: A fotók, a leolvasási napló és az AI modellek kizárólag a készüléken futnak, nem távoznak a telefonról.

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
- **Közvetlen REST API Szinkron**: Az ellenőrzött leolvasás egyetlen gombnyomással szinkronizálható a Home Assistant `gas_photo` integrációval.
- **Időbélyeg-alapú Idempotencia**: Megelőzi a duplikált beküldéseket.
- **Csökkenés Elleni Védelem**: Nem engedi beküldeni a korábbi óraállásnál kisebb értéket.
- **Biztonságos Keychain Tárolás**: A Home Assistant URL és a Long-Lived Access Token az iOS biztonságos hardveres kulcstárában (`iOS Keychain`) tárolódik.

### 5. 🔄 Telefonon Futó Modell-újratanítás (On-Device Training)
- **Helyi Példatár (Training Example Store)**: Minden manuálisan jóváhagyott vagy javított leolvasást tanítópéldaként megőriz a SwiftData adatbázisban.
- **ONNX Runtime Training**: A készülék képes helyben, közvetlenül az iPhone-on finomhangolni a számjegyosztályozó modellt, külső szerver bevonása nélkül.
- **Akkumulátor- és Töltésvédelem**: Csak akkor indítható el, ha a telefon töltőre van csatlakoztatva.

---

## 🏗️ Architektúra és Mappa-struktúra

```
GasPhotoIOS/
├── App/
│   ├── GasPhotoIOSApp.swift          # Alkalmazás belépési pont
│   ├── AppContainer.swift             # Dependency Injection & Service Factory
│   └── RootView.swift                 # Fő navigációs tabok (Kamera, Előzmények, Beállítások)
├── Domain/
│   ├── Reading.swift                  # Leolvasás modell (állapotok, normalizált érték)
│   ├── ReadingValidator.swift         # 8 jegyű formátum és csökkenés-ellenőrzés
│   └── ModelTrainingDomain.swift      # Tanítási állapotgépek és konfigurációk
├── Features/
│   ├── Capture/                       # Élő kamera nézet, Apple Intelligence szkenner HUD
│   ├── Review/                        # Leolvasás-ellenőrző, görgőtárcsák, finomhangolás
│   ├── History/                       # SwiftData leolvasási napló, szűrés, szinkronizáció
│   ├── Training/                      # On-device modell tanítás vezérlőpult
│   └── Settings/                      # Home Assistant kapcsolat és token beállítások
├── Inference/
│   ├── InferenceService.swift         # YOLOv8 és roller klasszifikáció orchestrator
│   ├── ONNXRuntime.swift              # Swift burkoló az ONNX futtatókörnyezethez
│   ├── ORTInferenceBridge.[h|mm]      # C++ / Objective-C++ híd az onnxruntime-c könyvtárhoz
│   └── ModelBundle.swift              # Beágyazott .onnx modellek feloldása
├── Data/
│   ├── SwiftDataReadingRepository.swift
│   └── SwiftDataTrainingExampleStore.swift
└── Photos/
    ├── CameraCaptureService.swift     # AVFoundation 4K fotórögzítés
    └── PhotoArchive.swift             # SHA-256 hash alapú helyi képmentés
```

---

## 🚀 Fejlesztői Környezet és Beállítás

### Előfeltételek
- **macOS Sequoia** (vagy újabb)
- **Xcode 16+** (iOS 18+ SDK / iOS 26 Deployment Target)
- **CocoaPods** (`brew install cocoapods` vagy `gem install cocoapods`)

### Telepítés és Indítás

1. Klónozd a tárolót:
   ```bash
   git clone https://github.com/M3NT1/GAS_METER_READER_IOS.git
   cd GAS_METER_READER_IOS
   ```

2. Telepítsd a CocoaPods függőségeket (ONNX Runtime Mobile C/C++ csomag):
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

A teljes tesztcsomag futtatása terminálból:
```bash
xcodebuild test \
  -workspace GasPhotoIOS.xcworkspace \
  -scheme GasPhotoIOS \
  -destination "platform=iOS Simulator,id=1EA06092-5C2F-4760-BCE2-BA712AE07EF2"
```

**Teszteredmények:**
- ✅ **48 / 48 teszt sikeres** (`** TEST SUCCEEDED **`)
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
