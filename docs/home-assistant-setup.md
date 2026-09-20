# Home Assistant Integrációs Útmutató (Vigavi)

*Utolsó ellenőrzés dátuma: 2026-09-20*

Ez a dokumentum a Vigavi iOS alkalmazás és a Home Assistant integrációjának lépéseit részletezi.

---

## 1. Önálló használat és kompatibilitás
- A Vigavi használatához sem Home Assistant, sem HACS nem kötelező.
- A Vigavi teljes értékű, önálló mérőóra-naplóként működik offline módban is villany-, gáz- és vízórákhoz.
- A jelenlegi Home Assistant szinkronizáció kizárólag a szabványos 5 egész és 3 tört jegyes gázórát (`gas_main`) támogatja a meglévő egyedi integrációval.
- A villany- és vízórák, valamint az egyéb formátumú mérők adatai kizárólag helyben, a telefon biztonságos tárhelyén tárolódnak.

## 2. Szükséges egyedi integráció
- A gázóra adatok fogadását a Home Assistant oldalon a [home-assistant-gas-photo](https://github.com/M3NT1/home-assistant-gas-photo) egyedi komponens végzi.
- A Home Assistant iOS Companion alkalmazás, MQTT bróker vagy ESP32 mikrovezérlő nem előfeltétele a működésnek.
- Az integráció a Home Assistant REST API-ján keresztül fogadja a jóváhagyott leolvasásokat.

## 3. Telepítés HACS használatával
- Nyisd meg a HACS felületét a Home Assistantban.
- A jobb felső sarokban válaszd az „Egyedi tárolók” (Custom repositories) menüpontot: [HACS egyedi tárolók kezelése](https://www.hacs.xyz/docs/use/repositories/dashboard/).
- Add meg a tároló URL-jét: `https://github.com/M3NT1/home-assistant-gas-photo`
- Kategóriaként válaszd az `Integration` opciót, majd kattints a Hozzáadás és Letöltés gombra: [HACS letöltési útmutató](https://www.hacs.xyz/docs/use/download/download/).

## 4. Kézi telepítés
- Töltsd le a repó tartalmát a GitHubról: [home-assistant-gas-photo forráskód](https://github.com/M3NT1/home-assistant-gas-photo).
- Másold át a repóban található `custom_components/gas_photo` mappát a Home Assistant szervered `/config/custom_components/gas_photo` útvonalára.
- A forráskód közvetlenül használható, nincs szükség előre csomagolt kiadásra.

## 5. YAML konfiguráció
A meglévő `configuration.yaml` megtartásával add hozzá a következő konfigurációs blokkot:

```yaml
gas_photo:
  max_m3_per_hour: 6
```

- A `max_m3_per_hour` (alapértelmezés: 6) a gázóra fizikai óránkénti kapacitásához (`Qmax`) igazítandó.
- Mentsd el a fájlt, ellenőrizd a konfigurációt a Fejlesztői eszközökben, majd indítsd újra a Home Assistantot.

## 6. Hozzáférési token készítése
- A Home Assistant felületén kattints a profilodra (bal alsó sarok), majd görgess a „Biztonság” szekcióhoz.
- A „Hosszú élettartamú hozzáférési tokenek” résznél hozz létre egy új tokent (pl. `Vigavi iOS`): [Home Assistant hitelesítési dokumentáció](https://www.home-assistant.io/docs/authentication/).
- **Fontos:** a jelenlegi leolvasás-importáláshoz adminisztrátori felhasználói fiók tokenje szükséges.
- Másold ki a tokent, és kizárólag a Vigavi alkalmazás beállításaiban található biztonságos mezőbe illeszd be. A token soha ne kerüljön nyilvános helyre!

## 7. Csatlakozás és ellenőrzés
- Kapcsold be a „Home Assistant használata” kapcsolót a Vigaviban.
- Add meg a szerver helyi vagy külső címét (pl. `192.168.0.99:8123` vagy `https://homeassistant.local:8123`) és a tokent.
- Érintsd meg a „Kapcsolat tesztelése” gombot.
- A sikeres teszt azt igazolja, hogy a REST API és a `gas_photo` szolgáltatás elérhető. Nem igazolja előre az importálási jogosultságot vagy az Energy panel statisztika meglétét.

## 8. Első feltöltés és Energy panel
- Készíts egy fotót a gázóráról, ellenőrizd és hagyd jóvá az állást, majd töltsd fel a Home Assistantba.
- Nyisd meg a Home Assistant Beállítások → Irányítópultok → Energia (Energy) menüjét: [Home Assistant Energy dokumentáció](https://www.home-assistant.io/docs/energy/).
- A „Gázfogyasztás” szekcióban adj hozzá egy új gázforrást, és válaszd a `gas_photo:gas_main` entitást.
- Egyetlen leolvasásból a Home Assistant még nem tud fogyasztást számolni; a statisztika az első órás periódus és a következő leolvasás után válik láthatóvá.

## 9. Hibaelhárítás
- **Nem elérhető szerver / időtúllépés:** ellenőrizd az IP-címet, portot (alapértelmezetten 8123) és hogy az iPhone ugyanahhoz a helyi hálózathoz csatlakozik-e.
- **401 Nem jogosult (Unauthorized):** a token hibás, lejárt vagy visszavonásra került.
- **403 Tiltott (Forbidden):** a tokenhez tartozó felhasználó nem rendelkezik adminisztrátori jogosultsággal.
- **404 Nem található:** a `custom_components/gas_photo` nincs megfelelően telepítve vagy a Home Assistant még nem lett újraindítva.
- **Helyi mentés:** a Home Assistant hibái soha nem akadályozzák meg a leolvasás helyi mentését a telefonon (`Helyben mentve` státusz).
