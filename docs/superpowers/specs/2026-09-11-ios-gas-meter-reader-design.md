# iOS Gázóra-leolvasó alkalmazás terve

## Cél és hatókör

Az alkalmazás iOS 26-tól, iPhone 14 Pro Max-en futó, helyi gázóra-leolvasó. A felhasználó a telefonnal készít képet a Sacofgas G4 mérőről. Az alkalmazás a teljes képen megkeresi a kizárólag fekete–piros nyolcgörgős számlálóablakot, javaslatot tesz a leolvasásra, majd kézi javítás vagy jóváhagyás után feltölti azt a meglévő Home Assistant `gas_photo` egyedi integrációba.

Nincs automatikus jóváhagyás vagy automatikus feltöltés. A felismerés és a fotóarchívum a telefonon marad. A Home Assistant kizárólag a jóváhagyott leolvasási adatot kapja meg.

## Platform és függőségek

- SwiftUI, Swift Concurrency és iOS 26.
- AVFoundation kamera, ImageIO metadata-olvasás és CryptoKit SHA-256.
- ONNX Runtime Mobile iOS futtató- és on-device training csomag, Swift–Objective-C hídon keresztül.
- Beágyazott, változatlan modellek:
  - `window-detector/weights/best.onnx` — keretdetektor.
  - `digit-classifier/weights/active.onnx` — éles számjegyosztályozó.
- A két modellhez a Macen, verziózott buildlépésben elkészített ONNX Runtime tanítási artefaktumok: tanító-, értékelő- és optimalizáló modell, valamint kezdő ellenőrzőpont. Ezek nélkül az app nem kínál tanítási gombot.
- SwiftData a csak helyi leolvasási naplóhoz; a képfájlok az alkalmazás Application Support könyvtárában élnek.

## Felhasználói folyamat

Az elfogadott felület az egyképernyős ellenőrző nézet.

1. A felhasználó a kezdőképernyőn új leolvasást indít és lefényképezi a teljes gázórát.
2. Az alkalmazás megőrzi az eredeti fotót, kiolvassa a rögzítési idejét, kiszámítja a SHA-256 azonosítót, majd helyben futtatja a keretdetektort.
3. A megjelenő fotón a számlálóablak zöld keretet kap. A felhasználó a keretet áthelyezheti és átméretezheti úgy, hogy csak a fekete és piros görgősor maradjon benne.
4. A számjegyfelismerő a kijelölt terület nyolc azonos szélességű részét olvassa. A felület az öt fekete egész és három piros tizedes számjegyet, valamint a görgőnkénti bizalmat mutatja.
5. A felhasználó szükség szerint felülírja a javaslatot. Az "Ellenőriztem, mentés" csak pontosan nyolc számjeggyel aktív.
6. Jóváhagyáskor a rekord tartós helyi küldési sorba kerül. Feltöltés csak külön, tudatos felhasználói műveletre indul.
7. Sikeres Home Assistant-import és pontos visszaolvasás után az állapot `synced`; egyébként `pendingSync`, újrapróbálható hibaleírással.
8. A Beállítások / Modell tanítása nézetben a felhasználó áttekintheti a jóváhagyott, címkézett példákat, és manuálisan új jelöltmodellt taníthat, ha eléri a minimumot. A tanítás a telefonon fut, csak akkor indul, ha a készülék töltőn van és a felhasználó megerősíti.

## Felismerési szabályok

A pipeline a Mac alkalmazás viselkedését követi.

- Csak egyetlen detektor-eredmény használható; több jelölt, hiányzó jelölt vagy 0,55 alatti bizalom esetén kizárólag kézi keretkijelölés lehetséges.
- A keretdetektor az eredeti képből 960 px-es modellbemenetet kap; a kapott koordináták az eredeti kép koordinátáira normalizálva tárolódnak.
- A kiválasztott keret nyolc azonos görgőkivágásra oszlik. A számjegymodell minden kivágást külön, 128 px-es bemenettel értékel.
- Az első öt számjegynél 0,75, a három tizedesnél 0,50 a minimális bizalom. A 0,50 és 0,75 közötti tizedes javaslat megjelenik, de figyelmeztetést kap.
- A kijelölt területen kívüli feliratok, vonalkód és gyári szám nem részei a felismerési bemenetnek.
- A modell nem következtet számjegyet korábbi fogyasztásból, és minden javaslat `needsReview` állapotú.

## Telefonon történő modelltanítás és -frissítés

A telefon a jóváhagyáskor keletkező keret- és nyolc számjegycímkét az alkalmazás saját, iOS Data Protectiontel védett és alkalmazáson kívül nem exportált helyi tanítóhalmazában tárolja. A tanítás nem küld fotót, címkét vagy modellt a Home Assistantba vagy külső szolgáltatóhoz.

- A teljes modellek nulláról tanítása nem része a telefonos folyamatnak. A Macen előállított, előtanított modellekhez készülő ONNX Runtime tanítási artefaktumok csak a finomhangolásra kijelölt rétegeket teszik taníthatóvá.
- A keretdetektor és a számjegyosztályozó külön tanítási munkamenet. Mindkettőhöz legalább 40 jóváhagyott, változatos fotó kell; egy fotó mind a nyolc számjegye ugyanabba a tanító-, validációs vagy tesztcsoportba kerül.
- A készülék időben és képsorozatonként elkülönített 80/10/10 tanító-, validációs- és tesztcsoportot képez. A tesztpéldák nem vehetnek részt a finomhangolásban.
- A háttérfolyamat állapota, előrehaladása és energiaigénye látható. Az app a tanítás alatt is használható; az iOS által megszakított munkamenet nem teheti aktívvá a félkész modellt.
- A végeredmény mindig `candidate` modell. Az app a tartott tesztkészleten kiértékeli a keret IoU-ját, a teljes érték egyezését és a görgőbizalmakat. Csak akkor jelenik meg az "Aktiválás" lehetőség, ha nincs magas bizalmú hibás javaslat, a teljes érték és a keretmutató nem romlik az aktív modellhez képest, valamint a számjegymodell top-1 eredménye legalább 90%.
- Az aktiválás külön, megerősített felhasználói művelet. Az előző modell megmarad, a váltás auditálható és egy gombbal visszavonható. A friss modell kizárólag ezen az iPhone-on lesz aktív.
- A Beállításokban megjelenik az aktív és jelölt modell verziója, a tanítópéldák száma, a teszteredmény és a visszaállítási lehetőség. A modellfájlokat a rendszer Application Support alatti, alkalmazáson kívül nem megosztott könyvtárban tartja.

## Helyi adatok és audit

Minden rekordban szerepel az egyedi azonosító és revízió, a `gas_main` mérőazonosító, az eredeti kép relatív útvonala és SHA-256 azonosítója, a pontos rögzítési idő, a keret koordinátái, a gépi javaslat és bizalmak, a kézzel véglegesített érték, a döntés, a modellverzió, az állapot és a legutóbbi szinkronhiba. Külön modell- és értékelési rekord tárolja a tanítóhalmaz-ujjlenyomatot, a modell státuszát (`candidate`, `active`, `rejected`, `superseded`), a tanítás beállításait és a teszteredményeket.

Az ImageIO által beolvasott eredeti fotóidő az irányadó; jóváhagyáskor nem szerkeszthető. Az eredeti fotó nem módosul. A vezető nullák az auditált nyolc számjegyben megmaradnak, a Home Assistantnak küldött `Decimal` értékből viszont eltűnnek.

## Home Assistant

A Beállításokban a felhasználó a saját Home Assistant HTTPS-címén jelentkezik be OAuth 2 / PKCE segítségével. Az access- és refresh-token iOS Keychainbe kerül. Nincs token a SwiftData-adatbázisban, fájlban, logban vagy a diagnosztikai képernyőn.

Kapcsolatkor az alkalmazás lekéri a `/api/config` és `/api/services` erőforrásokat, és ellenőrzi a `gas_photo` szolgáltatást. Feltöltéskor `POST /api/services/gas_photo/import_readings?return_response` hívást indít, majd `POST /api/services/gas_photo/get_readings?return_response` hívással egyezteti az azonosítót, revíziót, mérőt, decimális értéket és offsetes időt. Az app a `service_response` burkolatból olvas.

401 esetén a Keychain-tokenek törlődnek, a jóváhagyott rekord megmarad és a felület új belépést kér. Kapcsolati, szerver- vagy visszaolvasási hiba esetén nincs részleges `synced` állapot: a rekord újrapróbálható várólistán marad.

## Hibakezelés

- Kamera- vagy metadata-hiba: az app nem hoz létre jóváhagyható rekordot.
- Felismerési hiba: a felhasználó teljesen kézzel húzhat keretet és írhat értéket.
- Érvénytelen érték: csak öt egész és három tizedes számjegy fogadható el.
- Hiányzó modell vagy modellfutási hiba: kézi út marad használható, hibajelzéssel.
- Home Assistantban hiányzó integráció vagy elérhetetlen szerver: küldés nem indul, a rekord helyben marad.

## Tesztelés és elfogadás

Egységtesztek fedik a nyolc számjegyes formátumot, a küszöböket, a vezető nullák küldési értékét, a keret-validációt, a lokális rekordállapotokat, a Keychain hibakategóriáit és a Home Assistant-válaszok feldolgozását. Integrációs tesztek hamis HTTP-kiszolgálóval igazolják a feltöltés–visszaolvasás egyezést, a 401-es újrahitelesítést és a hibás `service_response` elutasítását.

A modelladapter tesztjei a meglévő referenciafotókon ellenőrzik a 960 px-es keret- és 128 px-es görgőbemenetet, valamint az iOS és Mac eredményének egyezését. A tanítási tesztek igazolják a minimum példaszámot, a fotócsoportonkénti felosztást, a megszakított tanítás biztonságát, a jelöltmodell értékelését, az aktiválási korlátokat és a visszaállítást. Eszközteszten a kamera által készített eredeti képből megmarad a pontos rögzítési idő, a keret szerkeszthető, és manuális megerősítés nélkül nem hívható Home Assistant-szolgáltatás.

## Nem része ennek a verziónak

- iOS 26-nál régebbi rendszer támogatása.
- Távoli vision/OCR szolgáltatás vagy automatikus fotófeltöltés.
- Automatikus jóváhagyás, fogyasztási trendből történő számjegypótlás vagy Home Assistant Energy-beállítás módosítása.
