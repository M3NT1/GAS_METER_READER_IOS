import Foundation

struct SetupGuideLink: Equatable, Sendable, Identifiable {
    var id: String { url.absoluteString }
    let title: String
    let url: URL
}

struct SetupGuideSection: Equatable, Sendable, Identifiable {
    var id: String { title }
    let title: String
    let summary: String
    let details: [String]
    let codeSnippet: String?
    let links: [SetupGuideLink]
}

enum HomeAssistantSetupGuide {
    static let lastVerified = "2026-09-20"

    static let sections: [SetupGuideSection] = [
        SetupGuideSection(
            title: "1. Önálló használat és kompatibilitás",
            summary: "A Vigavi használatához sem Home Assistant, sem HACS nem kötelező.",
            details: [
                "A Vigavi teljes értékű, önálló mérőóra-naplóként működik offline módban is villany-, gáz- és vízórákhoz.",
                "A jelenlegi Home Assistant szinkronizáció kizárólag a szabványos 5 egész és 3 tört jegyes gázórát (gas_main) támogatja a meglévő egyedi integrációval.",
                "A villany- és vízórák, valamint az egyéb formátumú mérők adatai kizárólag helyben, a telefon biztonságos tárhelyén tárolódnak."
            ],
            codeSnippet: nil,
            links: []
        ),
        SetupGuideSection(
            title: "2. Szükséges egyedi integráció",
            summary: "A gázállások fogadásához a home-assistant-gas-photo egyedi integráció szükséges.",
            details: [
                "A gázóra adatok fogadását a Home Assistant oldalon a home-assistant-gas-photo egyedi komponens végzi.",
                "A Home Assistant iOS Companion alkalmazás, MQTT bróker vagy ESP32 mikrovezérlő nem előfeltétele a működésnek.",
                "Az integráció a Home Assistant REST API-ján keresztül fogadja a jóváhagyott leolvasásokat."
            ],
            codeSnippet: nil,
            links: [
                SetupGuideLink(
                    title: "home-assistant-gas-photo tároló (GitHub)",
                    url: URL(string: "https://github.com/M3NT1/home-assistant-gas-photo")!
                )
            ]
        ),
        SetupGuideSection(
            title: "3. Telepítés HACS használatával",
            summary: "A legegyszerűbb telepítési mód a HACS egyedi tároló felvétele.",
            details: [
                "Nyisd meg a HACS felületét a Home Assistantban.",
                "A jobb felső sarokban válaszd az 'Egyedi tárolók' (Custom repositories) menüpontot.",
                "Add meg a tároló URL-jét: https://github.com/M3NT1/home-assistant-gas-photo",
                "Kategóriaként válaszd az 'Integration' opciót, majd kattints a Hozzáadás és Letöltés gombra."
            ],
            codeSnippet: nil,
            links: [
                SetupGuideLink(
                    title: "HACS letöltés és telepítés",
                    url: URL(string: "https://www.hacs.xyz/docs/use/download/download/")!
                ),
                SetupGuideLink(
                    title: "Egyedi tárolók kezelése a HACS-ben",
                    url: URL(string: "https://www.hacs.xyz/docs/use/repositories/dashboard/")!
                )
            ]
        ),
        SetupGuideSection(
            title: "4. Kézi telepítés",
            summary: "HACS nélkül a repó mappája közvetlenül is bemásolható.",
            details: [
                "Töltsd le a repó tartalmát a GitHubról.",
                "Másold át a repóban található custom_components/gas_photo mappát a Home Assistant szervered /config/custom_components/gas_photo útvonalára.",
                "A forráskód közvetlenül használható, nincs szükség előre csomagolt kiadásra."
            ],
            codeSnippet: nil,
            links: [
                SetupGuideLink(
                    title: "home-assistant-gas-photo forráskód",
                    url: URL(string: "https://github.com/M3NT1/home-assistant-gas-photo")!
                )
            ]
        ),
        SetupGuideSection(
            title: "5. YAML konfiguráció",
            summary: "Add meg a gas_photo bejegyzést a configuration.yaml fájlban.",
            details: [
                "A meglévő configuration.yaml megtartásával add hozzá a következő konfigurációs blokkot:",
                "A max_m3_per_hour (alapértelmezés: 6) a gázóra fizikai óránkénti kapacitásához (Qmax) igazítandó.",
                "Mentsd el a fájlt, ellenőrizd a konfigurációt a Fejlesztői eszközökben, majd indítsd újra a Home Assistantot."
            ],
            codeSnippet: "gas_photo:\n  max_m3_per_hour: 6",
            links: []
        ),
        SetupGuideSection(
            title: "6. Hozzáférési token készítése",
            summary: "Hosszú élettartamú adminisztrátori hozzáférési token szükséges.",
            details: [
                "A Home Assistant felületén kattints a profilodra (bal alsó sarok), majd görgess a 'Biztonság' szekcióhoz.",
                "A 'Hosszú élettartamú hozzáférési tokenek' résznél hozz létre egy új tokent (pl. 'Vigavi iOS').",
                "Fontos: a jelenlegi leolvasás-importáláshoz adminisztrátori felhasználói fiók tokenje szükséges.",
                "Másold ki a tokent, és kizárólag a Vigavi alkalmazás beállításaiban található biztonságos mezőbe illeszd be. A token soha ne kerüljön nyilvános helyre!"
            ],
            codeSnippet: nil,
            links: [
                SetupGuideLink(
                    title: "Home Assistant hitelesítési útmutató",
                    url: URL(string: "https://www.home-assistant.io/docs/authentication/")!
                )
            ]
        ),
        SetupGuideSection(
            title: "7. Csatlakozás és ellenőrzés",
            summary: "Állítsd be a címet és teszteld a kapcsolatot a Vigaviban.",
            details: [
                "Kapcsold be a 'Home Assistant használata' kapcsolót.",
                "Add meg a szerver helyi vagy külső címét (pl. 192.168.0.99:8123 vagy https://homeassistant.local:8123) és a tokent.",
                "Érintsd meg a 'Kapcsolat tesztelése' gombot.",
                "A sikeres teszt azt igazolja, hogy a REST API és a gas_photo szolgáltatás elérhető. Nem igazolja előre az importálási jogosultságot vagy az Energy panel statisztika meglétét."
            ],
            codeSnippet: nil,
            links: []
        ),
        SetupGuideSection(
            title: "8. Első feltöltés és Energy panel",
            summary: "Készíts egy ellenőrzött gázóra-leolvasást, és állítsd be az Energy panelt.",
            details: [
                "Készíts egy fotót a gázóráról, ellenőrizd és hagyd jóvá az állást, majd töltsd fel a Home Assistantba.",
                "Nyisd meg a Home Assistant Beállítások → Irányítópultok → Energia (Energy) menüjét.",
                "A 'Gázfogyasztás' szekcióban adj hozzá egy új gázforrást, és válaszd a gas_photo:gas_main entitást.",
                "Egyetlen leolvasásból a Home Assistant még nem tud fogyasztást számolni; a statisztika az első órás periódus és a következő leolvasás után válik láthatóvá."
            ],
            codeSnippet: nil,
            links: [
                SetupGuideLink(
                    title: "Home Assistant Energy beállítási útmutató",
                    url: URL(string: "https://www.home-assistant.io/docs/energy/")!
                )
            ]
        ),
        SetupGuideSection(
            title: "9. Hibaelhárítás",
            summary: "Gyakori problémák és megoldásaik.",
            details: [
                "Nem elérhető szerver / időtúllépés: ellenőrizd az IP-címet, portot (alapértelmezetten 8123) és hogy az iPhone ugyanahhoz a helyi hálózathoz csatlakozik-e.",
                "401 Nem jogosult (Unauthorized): a token hibás, lejárt vagy visszavonásra került.",
                "403 Tiltott (Forbidden): a tokenhez tartozó felhasználó nem rendelkezik adminisztrátori jogosultsággal.",
                "404 Nem található: a custom_components/gas_photo nincs megfelelően telepítve vagy a Home Assistant még nem lett újraindítva.",
                "Helyi mentés: a Home Assistant hibái soha nem akadályozzák meg a leolvasás helyi mentését a telefonon (Helyben mentve státusz)."
            ],
            codeSnippet: nil,
            links: []
        )
    ]
}
