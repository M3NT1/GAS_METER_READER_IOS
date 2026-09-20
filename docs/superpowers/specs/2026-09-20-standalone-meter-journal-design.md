# Önálló mérőóra-napló és opcionális Home Assistant — tervezet

Dátum: 2026-09-20. Állapot: tervezési dokumentum, implementáció még nincs.
Feature branch: `codex/standalone-meter-journal`.

## Cél és elfogadott scope

Az alkalmazás Home Assistant nélkül is tárolja és jelenítse meg több villany-, gáz- és vízóra leolvasásait és a leolvasások közötti fogyasztást. Fotózáskor konkrét mérőt lehessen választani; a kategória a mérő tulajdonsága. A Beállítások tartalmazzanak offline olvasható HA-telepítési útmutatót hivatalos és projektlinkekkel.

A felhasználó kifejezetten elfogadta, hogy villany- és vízóránál az első változat fotó + kézi bevitel legyen. A meglévő gázóra automatikus felismerése, kézi keretkorrekciója és ellenőrzése megmarad. Új általános OCR, új modellek tanítása, felhőszolgáltatás és a HA-szerver többórás átalakítása nem része ennek a fejlesztésnek. A korábban kért valódi telefonos tréning továbbra is külön fennálló feladat; ez a terv nem nyilvánítja késznek és nem szünteti meg.

## Jelenlegi, kódból ellenőrzött kiindulópont

| Terület | Jelenlegi állapot | Tervezett minimális bővítés |
| --- | --- | --- |
| `MeterReading` | Már tartalmaz `meterID`, `capturedAt`, `photoID`, revízió mezőket | Azonosítók és fotókapcsolatok megtartása |
| `CaptureViewModel` | Két helyen rögzített `gas_main` | Kiválasztott mérő pillanatképe a fotózási/importfolyamat elején |
| `ReadingValidator`, tárcsák | Fix 5+3 jegy | Régi validátor megtartása, külön formátumfüggő belépés |
| `ReviewViewModel.approve` | Helyben ment, `pendingSync` állapot, külön feltöltés | HA nélküli mentett állapot; mérőnkénti validáció |
| Növekményellenőrzés | Jelenleg minden mérőt együtt nézne | Kötelező `meterID` szűrés |
| `SwiftDataReadingRepository` | Tartós napló, optimista revízióellenőrzés | Megtartás; külön mérőtábla és adatvesztésmentes migráció |
| HA kliens | Import, visszaolvasás, stabil külső ID, Keychain | Megtartás; minden hívási pont előtt közös engedélyezési szabály |
| Training | Példatároló működik, tanítási szolgáltatás szimuláció | Meglévő minták megőrzése; idegen formátum ne kerülhessen a gáztréningbe |

A szerver ellenőrzött verziója: `M3NT1/home-assistant-gas-photo@0ccb7a37301851f604169c7e3efa68c0f3fc00ab`. A `ledger.py` csak `meter_id == gas_main`, `source == manual_review` adatot fogad; a statisztika fix `gas_photo:gas_main`, `m³`. Az import adminisztrátor jogosultságú HA-felhasználót követel. A kliens kapcsolattesztje olvasási próbával ezt az írási jogosultságot még nem bizonyítja.

## Megvizsgált irányok

1. **Meglévő helyi napló bővítése, opcionális HA — javasolt.** A SwiftData, kamera, fotóarchívum, gázfelismerés és REST kliens megmarad; mérőkatalógus, formátum, fogyasztásszámítás és HA-kapcsoló egészíti ki. Kevés új függés, lépcsőzetesen ellenőrizhető változások.
2. **HA helper/Utility Meter központú megoldás.** Kézi értékekhez használható, de önálló iOS használatot nem ad. Az utólag megadott fotóidő és a jelenlegi pontos ledger kezelését nem helyettesíti. Nem választjuk.
3. **Új általános mérő/OCR keretrendszer vagy a teljes adatréteg cseréje.** Nagyobb migrációs és felismerési kockázat, a működő gázfolyamat elvesztésének veszélye. Nem indokolt az első változathoz.

## Adatmodell: kategória helyett konkrét mérőhöz kötött napló

Új `Meter` tartományi típus és `PersistedMeter` SwiftData modell. Mezők:

- `id: String`: stabil azonosító; a régi mérőé változatlan `gas_main`, az újé UUID szövege.
- `name: String`, `kind: MeterKind` (`electricity`, `gas`, `water`). Azonos kategóriából több mérő lehet.
- `format: MeterFormat`: egészjegyek száma 1–9, tizedesjegyek száma 0–3; mértékegység kategóriából: villany `kWh`, gáz/víz `m³`.
- `recognition: RecognitionProfile`: `legacyGas8` vagy `manual`. Csak a bizonyított 5+3 gázprofil használja a meglévő ONNX útvonalat; a kategória önmagában nem bizonyít AI-kompatibilitást.
- `isArchived: Bool`: a mérő archiválható, a kapcsolódó leolvasások nem törlődnek.

Új mérő alapértékei: villany 6+3 kézi, víz 5+3 kézi, gáz 5+3 kézi; létrehozáskor a felhasználó beállítja a saját óra formátumát. A migrált `gas_main` változatlan 5+3 `legacyGas8` profilt kap. Új kompatibilis gázóránál a profil választható, de HA-ba akkor sem küldhető a jelenlegi szerverrel.

Az első leolvasás után a kategória, a mértékegység és a formátum nem változtatható meg visszamenőleg; név és archiváltság igen. Mérőcserénél új mérőazonosító indul, az előző archiválódik. Automatikus átfordulás/nullázás és tarifák közti számítás nem része az első változatnak.

A `MeterReading.meterID` meglévő mezőjét használjuk; nem kell minden régi rekordnak új UUID vagy új adatbázis. Az értékek kanonikus decimális szövegként maradnak tárolva; számításhoz `Decimal`, nem `Double` használandó. A magyar vesszős bevitelt pontosságvesztés nélkül normalizáljuk. ASCII számjegyek, egyetlen elválasztó, nincs negatív érték, exponenciális vagy ezreselválasztós bevitel. A kézi mező megengedi a rövidebb egészrészt, mentéskor a konfigurált szélességre nulláz; a régi 5+3 belépési pont viselkedése változatlan.

## Állapot és opcionális HA

Kisebb bővítésként új `approvedLocal` eset kerül a meglévő `ReadingStatus` mellé. A többi raw value megmarad, nem írjuk át a teljes állapotgépet.

| Esemény | Eredmény |
| --- | --- |
| Új telepítés | HA kikapcsolva, helyi használat az alap |
| Meglévő telepítés első migrációja | Korábbi Keychain-konfiguráció esetén HA bekapcsolva; token nélkül kikapcsolva |
| Jóváhagyás, HA ki vagy nem támogatott mérő | `approvedLocal`, „Helyben mentve”, nincs HA-hiba |
| Jóváhagyás, HA be, támogatott `gas_main` | Meglévő `pendingSync`; nincs automatikus feltöltés |
| Explicit feltöltés | Csak engedélyezett HA + `gas_main` + 5+3 gázprofil + jóváhagyott érték + hitelesítő adatok mellett |
| HA-hiba | Helyi érték és fotó megmarad; nincs téves `synced` |
| HA kikapcsolása | Új kérések nem indulnak, rekordok/revíziók/token nem törlődnek |
| HA visszakapcsolása | Nincs automatikus tömeges történeti feltöltés |

A HA-beállítás helyi, nem titkos `UserDefaults` érték, egyszeri inicializálási jelzővel; későbbi explicit kikapcsolást a meglévő token nem írhat felül. A token kizárólag Keychainben marad. Külön „Kapcsolat adatainak törlése” művelet lehet a meglévő törlési funkcióhoz igazítva.

Minden belépési pont ugyanazt a szabályt alkalmazza: review feltöltés/újraküldés, előzmény egyedi/tömeges küldés, kapcsolatteszt. A kliens protokollját, HTTP payloadját és visszaolvasását nem cseréljük. A ki kapcsoló mentésekor már folyamatban levő kérés befejeződhet; ezt a UI jelzi, új kérés és a tömeges sor következő eleme nem indul. Az eredmény helyi mentése kikapcsolás esetén is megtörténhet, ha a kérés már teljesült.

A régi `pendingSync` és `synced` adatok változatlanok maradnak. HA ki állapotban az előzmények elsődleges címkéje „Helyben mentve”; korábbi szinkron információ külön részletként látható. A jóváhagyott helyi sorok nem lesznek hibaállapotúak. Visszakapcsolás után az egyedi, explicit feltöltés felajánlható; a meglévő „függőben levők feltöltése” csak a tényleges `pendingSync` sorokat érinti, nem az összes `approvedLocal` történeti adatot.

## Felhasználói folyamat

1. Beállítások → Mérőórák: létrehozás, név, kategória, formátum, archiválás. Üres új telepítésen a kamera először mérő létrehozását kéri.
2. Kamera tetején a konkrét mérő neve és kategóriája; az utoljára használt aktív mérő megjegyezhető. Fotózás és könyvtári import előtt kiválasztható.
3. Exponálás/import indításakor rögzítjük a kiválasztott mérőt. Folyamat közbeni váltás nem címkézheti át a készülő rekordot. A review-n látható a mérő neve és egysége.
4. `legacyGas8`: meglévő detector → keretszerkesztő → tárcsák → ellenőrzés. `manual`: fotó + decimális billentyűzet + egyértelmű egység; nem fut a gázmodell.
5. „Jóváhagyás és mentés”: helyben, hálózat nélkül működik. Gáztréningmintát csak a megfelelő profillal, jóváhagyott értékkel és kerettel készítünk. Az előzményből indított kézi tréningminta-regisztrációra is vonatkozik.
6. Előzmények: mérőnkénti szűrés, kategória, óraállás, dátum, fotó és két leolvasás közti fogyasztás. A meglévő navigációt bővítjük; nincs teljes felületi újratervezés.
7. Beállítások → Home Assistant: használati kapcsoló, telepítési útmutató, majd bekapcsolva a meglévő URL/token és kapcsolatteszt. Az útmutató kikapcsolt HA mellett is olvasható.

## Fogyasztás és időkezelés

Csak jóváhagyott, azonos mérőhöz tartozó értékekből számítunk, `capturedAt` szerint. Az első érték alapállás; fogyasztása „—”, nem nulla. Két egymást követő érték különbsége az adott két időpont közötti fogyasztás, pl. 12345.100 → 12347.450 = 2.350 m³. Egyenlő állás eltérő időben valódi 0 fogyasztás.

A később bevitt régebbi fotó a helyes időpontra kerül; a két szomszédos intervallum újraszámolódik. Törléskor is újraszámítunk. A gáz, víz és villany értékeit nem összegezzük egymással. Azonos mérő + azonos időpont + eltérő érték konfliktus, nem két független mérés; ugyanazon érték duplikált jóváhagyása sem ad plusz fogyasztást. A negatív különbség felülvizsgálati hiba, nem automatikus mérőreset.

A fotó eredeti készítési ideje és rész-másodpercei megmaradnak; importidő vagy fájl-mtime nem helyettesítheti. Az EXIF nélküli import a meglévő hiányzó-idő hibát adja, nem talál ki dátumot. A megjelenítés helyi időzónás, összehasonlítás abszolút időpontokkal történik; DST sem rendezheti át az eseményeket.

Az MVP intervallumlistát és a kiválasztott mérő első/utolsó jóváhagyott leolvasása közötti összes fogyasztást mutatja, a tényleges lefedett időszakkal. Nincs megbecsült napi/havi bontás: ritka fotókból nem ismerhető meg a köztes napok fogyasztása. A szerver megfigyelési órához rendelt statisztikája külön megjelenítési szabály, az iOS számítás nem módosítja.

## SwiftData migráció és visszaállíthatóság

A jelenlegi, még nem verziózott `PersistedMeterReading` és `PersistedTrainingExample` séma pontos másolatából kell indulni; a meglévő adatfájl helyét nem változtatjuk. Először valódi, régi modellekkel létrehozott lemezes fixture-rel bizonyítani kell az új `PersistedMeter` hozzáadását és a megnyitást. `VersionedSchema`/`SchemaMigrationPlan` csak az igazolt legacy checksum megfeleléssel köthető be; ha a minimális additív séma automatikusan migrálható, ne legyen indokolatlan kézi rekordátírás.

Az egyszer futó katalógus-bootstrap minden meglévő `meterID`-hez létrehoz egy mérőt; a várt `gas_main` a legacy profilt kapja. Esetleges ismeretlen régi ID-t külön, archivált, kézi gázmérőként kell megőrizni és felülvizsgálatra jelölni a felületen, nem eldobni vagy összevonni. A katalógus frissítése idempotens; a kész jelző csak a sikeres mentés után írható. Sikertelen migrációnál nem töröljük és nem inicializáljuk üresre az adatbázist.

A migráció előtt az alkalmazás által zárt régi store-ról és a fotóarchívumról visszaállítható másolat kell. SQLite főfájl élő másolása önmagában nem elég (WAL/SHM). A teszt és a készülékes próba ellenőrzi a rekord-, fotó- és tréningmintaszámot, ID-ket, időket, értékeket, revíziókat és szinkronállapotokat. A régi binárisra visszatéréshez a régi store mentését kell visszaállítani; nem ígérünk visszafelé kompatibilis megnyitást.

## HA-útmutató: tervezett, alkalmazásba csomagolt tartalom

- Az önálló naplóhoz sem HA, sem HACS nem kell. A jelenlegi szinkron csak az eredeti `gas_main` gázórát támogatja.
- Szükséges komponens: [home-assistant-gas-photo](https://github.com/M3NT1/home-assistant-gas-photo), egyedi integráció. A Home Assistant iOS Companion, MQTT és ESP32 nem előfeltétel.
- HACS út: [HACS telepítés](https://www.hacs.xyz/docs/use/download/download/), egyedi tároló felvétele Integration kategóriával, letöltés. [HACS használat](https://www.hacs.xyz/docs/use/repositories/dashboard/).
- Alternatíva: a repó `custom_components/gas_photo` mappáját teljes egészében a HA `/config/custom_components/gas_photo` helyére másolni. A repó forrása használható; nem állítjuk, hogy mindig létezik kiadási csomag.
- Meglévő YAML megtartásával hozzáadás, konfiguráció-ellenőrzés, teljes HA-újraindítás:

```yaml
gas_photo:
  max_m3_per_hour: 6
```

A 6 csak példa/default; az óra fizikai maximumához igazítandó. Nem generálunk új teljes `configuration.yaml` fájlt.

- [Profil → Biztonság → hosszú élettartamú token](https://www.home-assistant.io/docs/authentication/). A jelenlegi import admin felhasználót igényel. Token beillesztése kizárólag a meglévő biztonságos mezőbe; útmutató/link/napló nem tartalmaz tokent.
- App → HA bekapcsolás → tényleges szervercím és token → kapcsolatteszt. Sikeres teszt: API és `gas_photo` olvasható; importjogot és Energy publikációt nem igazol.
- Egy valós, ellenőrzött gázállás kézi feltöltése és visszaolvasása. Az útmutató megnyitása/kapcsolatteszt nem ír tesztadatot a naplóba.
- [Energy beállítás](https://www.home-assistant.io/docs/energy/): Gázforrás → `gas_photo:gas_main`, amikor a statisztika már elérhető. Egyetlen alapállásból még nincs fogyasztás; a publikáció késhet. A gas-photo Lovelace kártya opcionális, nem feltétele az iOS működésének.
- Hibamagyarázatok: elérés/hálózat, 401 token, 403 jogosultság, hiányzó `gas_photo`, még üres statisztika; a helyi mentést egyik sem blokkolja. Nem állítjuk, hogy minden 500-as hiba fogyasztási határérték-probléma.

A szöveg helyben elérhető, csak a külső linkekhez kell hálózat; SwiftUI nézet és típusos útmutatóadat elegendő, nincs távoli HTML/WebView függés. Ellenőrzés dátuma szerepeljen.

## Kutatás és következtetések — 2026-09-20

Az alábbi források iránymutatások, nem kerülnek új függőségként a projektbe.

1. [Saját HA ledger, rögzített verzió](https://github.com/M3NT1/home-assistant-gas-photo/blob/0ccb7a37301851f604169c7e3efa68c0f3fc00ab/custom_components/gas_photo/ledger.py) és [szolgáltatások](https://github.com/M3NT1/home-assistant-gas-photo/blob/0ccb7a37301851f604169c7e3efa68c0f3fc00ab/custom_components/gas_photo/__init__.py): a fix szerződés miatt a villany/víz feltöltését a kliensben tiltjuk; megmarad az import/readback.
2. [AI-on-the-edge-device](https://github.com/jomjol/AI-on-the-edge-device): helyi kép → régiók → számfelismerés, többféle mérő és külön adatkimenetek. Saját következtetés: a felismerés profilja és az adatküldés váljon el; nem portoljuk az ESP32 projektet.
3. [homeassistant-statistics](https://github.com/klausj1/homeassistant-statistics): létezik fájlos hosszútávú statisztikaimport. Saját következtetés: későbbi exporthoz referencia, a bevált saját ledger lecserélésére nem indok.
4. [HA Utility Meter dokumentáció](https://www.home-assistant.io/integrations/utility_meter/) és [Energy FAQ](https://www.home-assistant.io/docs/energy/faq/): számlálóállás, ciklusos fogyasztás és statisztikai megfelelőség külön fogalmak. Nem vezetünk be HA helper-függőséget az önálló naplóba.
5. [Fórum: manual input](https://community.home-assistant.io/t/manual-input-of-meter-reading-in-energy-dashboard/598298), 2023: kézi/iOS OCR bevitel és Energy-beállítás körüli nehézség. A fórumot felhasználói tapasztalatként kezeltük; az útmutató követelményeit a jelenlegi szerverkód és hivatalos dokumentáció alapozza meg.
6. [Fórum: irregular manual readings](https://community.home-assistant.io/t/utility-meter-take-manual-readings/327418), 2021: ritka leolvasások és a napi grafikon értelmezési gondja. Saját termékdöntés: tényleges intervallumokat mutatunk, nem találunk ki órás/napi eloszlást.
7. [Apple SchemaMigrationPlan](https://developer.apple.com/documentation/SwiftData/SchemaMigrationPlan) és [WWDC25 migráció](https://developer.apple.com/videos/play/wwdc2025/291/): verziózott séma/migráció támogatott. A projekt régi, nem verziózott store-jának kompatibilitását külön teszt bizonyítja, nem pusztán e dokumentáció.

## Elfogadási kapuk

- Új telepítés, token nélkül és repülő módban: mindhárom kategória fotózása, jóváhagyása, újraindítás utáni visszaolvasása és fogyasztása működik; nulla HA-kérés.
- Régi adatbázis frissítése: azonos ID-k, fotók, időpontok, revíziók, tréningminták; új migráció ismétlése nem duplikál.
- Két vízóra és egy gázóra adatai, validációja és fogyasztása teljesen elkülönül.
- Régi gáz OCR/keret/tárcsák és explicit HA import/readback regressziómentesek.
- Villany/víz kézi adat soha nem indul gáz-ONNX-re, gáztréningre vagy a jelenlegi HA-fogadóra.
- Hiányzó EXIF-idő, ütköző időpont, csökkenés, köztes leolvasás, törlés, DST és vesszős bevitel célzott teszttel lefedett.
- HA ki/be kapcsolás nem töröl adatot, nem küld múltbeli rekordokat automatikusan.
- Fizikai iPhone 14 Pro Max/iOS 26+ smoke test és élő HA gázfeltöltés szükséges a kész funkció állításához.

## Átadás

Ez a dokumentum és a társított megvalósítási terv a feature branchen marad. A `main` ágra nem kerül feature-kód vagy automatikus merge. A következő fejlesztési kör GPT Terra számára adható át; most nem indul implementáció.
