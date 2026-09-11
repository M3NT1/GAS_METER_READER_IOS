# iOS Gázóra-leolvasó alkalmazás terve

## Cél és hatókör

Az alkalmazás iOS 26-tól, iPhone 14 Pro Max-en futó, helyi gázóra-leolvasó. A felhasználó a telefonnal készít képet a Sacofgas G4 mérőről. Az alkalmazás a teljes képen megkeresi a kizárólag fekete–piros nyolcgörgős számlálóablakot, javaslatot tesz a leolvasásra, majd kézi javítás vagy jóváhagyás után feltölti azt a meglévő Home Assistant `gas_photo` egyedi integrációba.

Nincs automatikus jóváhagyás vagy automatikus feltöltés. A felismerés és a fotóarchívum a telefonon marad. A Home Assistant kizárólag a jóváhagyott leolvasási adatot kapja meg.

## Platform és függőségek

- SwiftUI, Swift Concurrency és iOS 26.
- AVFoundation kamera, ImageIO metadata-olvasás és CryptoKit SHA-256.
- ONNX Runtime Mobile iOS csomag.
- Beágyazott, változatlan modellek:
  - `window-detector/weights/best.onnx` — keretdetektor.
  - `digit-classifier/weights/active.onnx` — éles számjegyosztályozó.
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

## Felismerési szabályok

A pipeline a Mac alkalmazás viselkedését követi.

- Csak egyetlen detektor-eredmény használható; több jelölt, hiányzó jelölt vagy 0,55 alatti bizalom esetén kizárólag kézi keretkijelölés lehetséges.
- A keretdetektor az eredeti képből 960 px-es modellbemenetet kap; a kapott koordináták az eredeti kép koordinátáira normalizálva tárolódnak.
- A kiválasztott keret nyolc azonos görgőkivágásra oszlik. A számjegymodell minden kivágást külön, 128 px-es bemenettel értékel.
- Az első öt számjegynél 0,75, a három tizedesnél 0,50 a minimális bizalom. A 0,50 és 0,75 közötti tizedes javaslat megjelenik, de figyelmeztetést kap.
- A kijelölt területen kívüli feliratok, vonalkód és gyári szám nem részei a felismerési bemenetnek.
- A modell nem következtet számjegyet korábbi fogyasztásból, és minden javaslat `needsReview` állapotú.

## Helyi adatok és audit

Minden rekordban szerepel az egyedi azonosító és revízió, a `gas_main` mérőazonosító, az eredeti kép relatív útvonala és SHA-256 azonosítója, a pontos rögzítési idő, a keret koordinátái, a gépi javaslat és bizalmak, a kézzel véglegesített érték, a döntés, a modellverzió, az állapot és a legutóbbi szinkronhiba.

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

A modelladapter tesztjei a meglévő referenciafotókon ellenőrzik a 960 px-es keret- és 128 px-es görgőbemenetet, valamint az iOS és Mac eredményének egyezését. Eszközteszten a kamera által készített eredeti képből megmarad a pontos rögzítési idő, a keret szerkeszthető, és manuális megerősítés nélkül nem hívható Home Assistant-szolgáltatás.

## Nem része ennek a verziónak

- iOS 26-nál régebbi rendszer támogatása.
- Telefonon történő modellbetanítás vagy modellfrissítés.
- Távoli vision/OCR szolgáltatás vagy automatikus fotófeltöltés.
- Automatikus jóváhagyás, fogyasztási trendből történő számjegypótlás vagy Home Assistant Energy-beállítás módosítása.
