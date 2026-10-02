# screengrab

Et enkelt skjermklippverktøy for macOS som ligger i menylinjen. Det bruker systemets eget områdevalg
(`screencapture -i`) og har et lite tegnevindu for piler, sirkler, rektangler, frihånd, markeringstusj, nummererte markører, tekst og sladding/uskarphet.

## Hurtigtaster (standard, kan endres i Innstillinger)

| Tast | Hva |
|---|---|
| ⌘⇧1 | Ta område → utklippstavlen |
| ⌘⇧2 | Ta område → åpne tegnevinduet (vinduet blir stående åpent) |
| ⌘⇧3 | Ta område → lagre rett i mappen |

Under områdevalget fungerer alt som med macOS sin ⌘⇧4: mellomrom velger et helt vindu, og Esc avbryter.

> **⚠️ ⌘⇧3 må slås av i macOS.** ⌘⇧3 er macOS sin egen snarvei for å ta bilde av hele skjermen.
> Så lenge den er på, tar macOS tastetrykket, og screengrab reagerer ikke. Slå den av i
> **Systeminnstillinger → Tastatur → Tastatursnarveier… → Skjermbilder**, og fjern haken for
> «Arkiver bilde av skjermen som en fil». Det samme gjelder hvis du velger ⌘⇧4 eller ⌘⇧5 for screengrab.
>
> screengrab sjekker dette selv. Ved oppstart kommer en advarsel (kan slås av med «Ikke vis igjen»),
> og så lenge konflikten finnes står den også i menyen og i Innstillinger, med en knapp som åpner
> Tastatur-innstillingene.

## Tegnevinduet

| Verktøy | Tast | |
|---|---|---|
| Velg og flytt | V | se under |
| Pil | A | ⇧ låser til 45° |
| Sirkel/ellipse | O | ⇧ gir perfekt sirkel |
| Rektangel | R | ⇧ gir kvadrat |
| Frihånd | P | |
| Markeringstusj | M | |
| Nummererte markører | N | hvert klikk gir neste nummer |
| Skjul | B | piksler, uskarp eller svart sladd |
| Tekst | T | se under |

- Farger: 1–8, eller valgfri farge fra fargevelgeren. Strektykkelse: tynn, middels eller tykk.
- ⌘Z angrer, ⌘⇧Z gjør om, ⌘W lukker uten å lagre.

**Tekst:** Klikk der teksten skal stå og skriv. ↩ avslutter, ⇧↩ gir ny linje og Esc forkaster.
Klikk på en eksisterende tekst for å endre den (tøm den for å slette den). Du kan velge mellom seks
lesbare fonter (SF Pro, Helvetica Neue, Arial, Verdana, Avenir Next og Georgia), 14–48 pt og fet skrift.
Teksten får en tynn kontrastkant, så den er lesbar på både lys og mørk bakgrunn.

**Velg og flytt:** Klikk på en figur for å velge den (stiplet ramme), og dra for å flytte den. ⌫ eller Delete
sletter, piltastene finjusterer (1 pt, eller 10 pt med ⇧) og Esc fjerner valget. Klikk på en farge for å gi den valgte
figuren ny farge, og dobbeltklikk på en tekst for å endre den. Ellipser og rektangler velges ved å klikke på streken,
så det som ligger inni dem fortsatt kan velges. Flyttes en sladd, hentes innholdet på nytt fra det nye stedet.

**Endre størrelse:** Dra i håndtakene på den valgte figuren. Piler har ett håndtak i hver ende. Ellipser, rektangler,
sladd og frihånd har åtte håndtak (hjørner og sidekanter), og frihånd skaleres med. Tekst og nummererte markører har
hjørnehåndtak og skaleres jevnt: tekst får større eller mindre skrift, og motsatt hjørne står fast.
Flytting, størrelse, sletting og fargeendring kan angres.

**Nummererte markører:** Hvert klikk setter ned en sirkel med neste nummer (1, 2, 3 …) i valgt farge. Dra mens
museknappen er nede for å flytte markøren på plass. Tykkelsesvalget styrer størrelsen. Neste nummer er alltid ett
høyere enn det høyeste i bildet, så rekkefølgen henger sammen også etter angre.

**Skjul:** Dra et rektangel over det som skal skjules, og velg variant i verktøylinjen. *Piksler* gjør området
om til store blokker, *Uskarp* gjør det uskarpt og *Sladd* dekker det med svart. Piksler og uskarphet hentes alltid
fra originalbildet. Svart sladd er sikrest for passord og lignende, fordi det ikke ligger noe igjen av innholdet.

**Kopier og Lagre** (oppførselen velges i Innstillinger):

| Knapp | Standard | Alternativer |
|---|---|---|
| Kopier (⌘C eller ↩) | Kopier, lagre og lukk | Kopier og lukk · Kopier (vinduet blir stående) |
| Lagre (⌘S) | Lagre og lukk | Lagre (vinduet blir stående) |
| Lagre som… (⌘⇧S) | følger innstillingen for Lagre | |

Det kopierte bildet kan limes rett inn i e-post eller chat. Lagring går til skjermbildemappen.
Et eksisterende bilde (åpnet fra fil) overskrives aldri: den første lagringen blir «<navn> – redigert.png».

Menyen har også «Tegn på siste skjermbilde» og «Åpne bilde for tegning…». `open -a screengrab bilde.png` fungerer også.

## Bygg og installer

Krever bare Command Line Tools (Swift), ikke Xcode.

```sh
sh build.sh      # swift build → build/screengrab.app, signert
sh install.sh    # ~/Applications + LaunchAgent (starter nå og ved innlogging)
```

## Oppdatere etter endringer i koden

Bygg på nytt og installer over den gamle versjonen. `install.sh` stopper appen som kjører,
bytter den ut og starter den igjen. Innstillinger og tillatelser blir stående.

```sh
cd ~/Git/screengrab && sh build.sh && sh install.sh
```

## Avinstallere

```sh
sh install.sh --fjern    # fjerner appen og LaunchAgent; innstillingene ligger igjen
defaults delete net.flagan.screengrab    # valgfritt: fjern også innstillingene
```

## Signering og tillatelser

Uten sertifikatet under blir appen ad hoc-signert. Den virker likevel, men macOS kan da be om tillatelsen
til Skjermopptak på nytt etter hver ny bygging.

Appen signeres med det selvsignerte sertifikatet fra screenlogger
(`~/Library/Keychains/screenlogger-sign.keychain-db`, identitet «screenlogger selvsignert»).
Signaturen er stabil mellom bygg, så tillatelsen til Skjermopptak blir stående.
Første gang ber macOS om tillatelse til Skjermopptak (Systeminnstillinger → Personvern og sikkerhet →
Skjerm- og systemlydopptak), og eventuelt om tilgang til OneDrive-filer.

Lagringsmappen er som standard den samme som macOS bruker for skjermbilder (Skjermbilde-appen ⌘⇧5 → Valg → Arkiver i),
ellers Skrivebordet. Den kan endres i Innstillinger.

## Feilsøking

- Logg: `~/Library/Application Support/screengrab/launchd.err.log`
- Kjører den? `pgrep -l screengrab`
- En hurtigtast merket «brukes av macOS» i menyen: slå av macOS-snarveien (se advarselen om ⌘⇧3 over).
- En hurtigtast merket «opptatt» brukes av en annen app. Velg en annen i Innstillinger.
- Advarselen ved oppstart kommer tilbake etter «Ikke vis igjen» med `defaults delete net.flagan.screengrab suppressSystemConflictWarning`.

## Filer

| Fil | Innhold |
|---|---|
| `Sources/screengrab/AppDelegate.swift` | menylinje, meny, opptak via `screencapture` |
| `Sources/screengrab/Editor.swift` | tegnevinduet, figurer, tekst, kopiering og lagring |
| `Sources/screengrab/Settings.swift` | innstillinger og innstillingsvindu |
| `Sources/screengrab/Hotkeys.swift` | globale hurtigtaster (Carbon, krever ingen Tilgjengelighet-tillatelse) |
| `mac/` | Info.plist, LaunchAgent og app-ikonet (`AppIcon.icns`) |
| `mac/lag-ikon.swift` | tegner app-ikonet: `swift mac/lag-ikon.swift` lager `mac/AppIcon.icns` på nytt |
| `build.sh`, `install.sh` | bygg, signering og installasjon |

## Lisens

MIT, se [LICENSE](LICENSE).
