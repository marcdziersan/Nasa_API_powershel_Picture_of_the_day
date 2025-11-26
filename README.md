# NASA-Powershell-Hacking  
## Dein Desktop, direkt aus dem All

Mit einer offiziellen Backdoor, der NASA API.

Kein Bock mehr auf den immer gleichen Windows-Hintergrund?  
Dieses Skript verbindet sich (legal!) mit der NASA, zieht sich täglich das aktuelle **Astronomy Picture of the Day (APOD)** und knallt es dir automatisch als Desktophintergrund drauf.

Einmal einrichten, für immer staunen.

---

## Was das Skript macht

- **Fragt deinen NASA-API-Key ab** (oder liest ihn aus `NASA_API_KEY`, wenn vorhanden)
- **Ruft die APOD-API auf** und holt sich die Metadaten zum Bild des Tages
- **Lädt das Bild herunter** und speichert es im Ordner:
  - Standard: `C:\Users\<DeinName>\Desktop\NasaBilder`
- **Setzt das Bild als Wallpaper**:
  - Direkt über die Windows-API (`SystemParametersInfo`)
- **Richtet auf Wunsch einen geplanten Task ein**:
  - Tägliche Ausführung um eine von dir gewählte Uhrzeit
  - Ruft dasselbe Skript mit dem Parameter `-Scheduled` auf
- **Merkt sich deine Einstellungen** in einer kleinen JSON-Config:
  - `nasa_apod_config.json` im gleichen Ordner wie das Skript

---

## Features im Überblick

- Einmal-Setup, danach komplett automatisch
- Fragt nach Adminrechten, wenn es sinnvoll ist (für den Task Scheduler)
- Erkennt, ob ein geplanter Task schon existiert – nervt dich nicht jedes Mal
- Funktioniert mit und ohne Leerzeichen im Skriptpfad
- Läuft im geplanten Modus komplett stumm:
  - Keine Pop-ups
  - Kein Output
  - Nur Bild holen und Hintergrund setzen

---

## Voraussetzungen

- Windows (10/11, mit Aufgabenplanung / Task Scheduler)
- PowerShell (Standard unter Windows)
- Internetzugang
- Ein eigener NASA-API-Key

### NASA-API-Key besorgen

1. Öffne: https://api.nasa.gov/
2. Formular ausfüllen (Name, E-Mail)
3. Du erhältst sofort einen **API-Key** im Browser und per Mail
4. Diesen Key kopierst du dir – du brauchst ihn im Setup

Optional: Du kannst den Key auch als Umgebungsvariable setzen:

```powershell
setx NASA_API_KEY "DEIN_API_KEY"
````

Dann liest das Skript ihn automatisch ein.

---

## Installation

### 1. Ordner anlegen

Lege dir einen Ordner an, z. B.:

```text
C:\Users\<DeinName>\Desktop\nasa
```

### 2. Skript speichern

Speichere die Datei als `Skript.ps1` in diesem Ordner.

Beispiel:

```text
C:\Users\<DeinName>\Desktop\nasa\Skript.ps1
```

### 3. Erste Ausführung

Öffne eine **normale** PowerShell (nicht unbedingt als Admin) und gehe in den Ordner:

```powershell
cd C:\Users\<DeinName>\Desktop\nasa
.\Skript.ps1
```

Beim ersten Start passiert Folgendes:

1. Das Skript prüft, ob es Adminrechte hat und bietet dir an, sich mit erhöhten Rechten neu zu starten (UAC-Prompt).

2. Es startet die **Ersteinrichtung**:

   * Fragt nach deinem NASA-API-Key (falls nicht in `NASA_API_KEY` gesetzt)
   * Zeigt dir den Standard-Ordner für Bilder (`Desktop\NasaBilder`) und lässt dich auf Wunsch einen anderen Pfad wählen
   * Prüft, ob es bereits eine geplante Aufgabe namens `NASA APOD Wallpaper` gibt
   * Bietet dir an, eine tägliche Aufgabe anzulegen und fragt nach der Uhrzeit (Standard: `08:00`)

3. Am Ende der Ersteinrichtung lädt es das aktuelle APOD-Bild und setzt es als Wallpaper.

Wenn alles geklappt hat, findest du das Bild z. B. hier:

```text
C:\Users\<DeinName>\Desktop\NasaBilder\2025-11-26 - Globular Cluster M15 Deep Field.jpg
```

---

## Wie das Skript intern arbeitet

### Config-Datei

Im gleichen Ordner wie das Skript liegt danach:

```text
nasa_apod_config.json
```

Darin stehen u. a.:

* `ApiKey`
* `TargetFolder`
* `RunTime` (für dich, aktuell nur informativ)
* `TaskCreated` (Merker, ob das Skript bereits versucht hat, den Task anzulegen)

Damit ist das Skript beim nächsten Start „smart“ genug, um dich nicht jedes Mal neu zu befragen.

### Geplante Aufgabe

Die Aufgabe heißt:

```text
NASA APOD Wallpaper
```

Sie startet:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<Pfad zu Skript.ps1>" -Scheduled
```

Wichtig:

* Im **Scheduled-Modus** (`-Scheduled`) läuft kein Setup, keine Rückfrage, kein UAC.
* Es wird nur:

  * die Config gelesen
  * das Bild des Tages geladen (falls noch nicht vorhanden)
  * dein Desktop-Hintergrund aktualisiert

---

## Manuelle Nutzung

Du kannst das Skript jederzeit manuell starten, um sofort das aktuelle APOD-Bild zu setzen:

```powershell
cd C:\Users\<DeinName>\Desktop\nasa
.\Skript.ps1
```

Wenn bereits alles eingerichtet ist:

* Keine Fragen mehr
* Bild wird aktualisiert
* Ausgabe zeigt nur kurz den Pfad des gesetzten Wallpapers

---

## Setup erzwingen / ändern

Wenn du das Setup später noch einmal bewusst durchlaufen möchtest (anderer Ordner, anderer Key, Task neu anlegen), kannst du das Skript mit `-ForceSetup` starten:

```powershell
cd C:\Users\<DeinName>\Desktop\nasa
.\Skript.ps1 -ForceSetup
```

Dann:

* werden API-Key, Zielordner und Task-Einrichtung erneut abgefragt
* wird die `nasa_apod_config.json` aktualisiert

---

## Typische Probleme & Lösungen

### 1. Aufgabe lässt sich nicht anlegen

Symptom: Rote Fehlermeldung à la „Access denied“ oder „Register-ScheduledTask…“.

Lösung:

* PowerShell **als Administrator** starten
* Ordner wechseln
* Skript erneut ausführen:

```powershell
cd C:\Users\<DeinName>\Desktop\nasa
.\Skript.ps1
```

Das Skript erkennt, dass noch kein Task existiert, und fragt erneut nach.

### 2. Kein Bild, weil APOD ein Video ist

Manchmal ist das Astronomy Picture of the Day ein Video (z. B. YouTube). In diesem Fall:

* erkennt das Skript `media_type = "video"`
* bricht einfach still ab
* lässt dein aktuelles Wallpaper unverändert

### 3. NASA-API-Key falsch oder gesperrt

Symptom:

* Manuelle Ausführung zeigt Fehlermeldung beim Abruf
* Oder es kommt gar kein Bild

Lösungen:

1. Key auf [https://api.nasa.gov](https://api.nasa.gov) kontrollieren oder neu generieren.
2. Script mit `-ForceSetup` starten und neuen Key eingeben.

---

## Sicherheit & Rechte

* Das Skript nutzt ausschließlich die **offizielle NASA-API**.
* Die API liefert öffentlich verfügbare Bilder und Metadaten.
* Es werden keine persönlichen Daten an NASA zurückgeschickt.
* Die Adminrechte werden nur benötigt, um die geplante Aufgabe sauber zu registrieren.
* Im normalen täglichen Betrieb (Task Scheduler) läuft der Job ohne erneute Rückfragen.

---

## Lizenz

Dieses Skript steht unter der **MIT-Lizenz**.

Kurzfassung:

* Du darfst den Code frei verwenden, anpassen und in eigene Projekte integrieren.
* Es gibt keine Garantie und keinen Support-Anspruch.
* Wenn du den Code weitergibst, solltest du die Lizenz beilegen.

---

## TL;DR

* Skript in einen Ordner legen
* PowerShell öffnen, Skript starten
* API-Key eingeben, Zielordner bestätigen, Uhrzeit wählen
* Fertig: Dein Desktop aktualisiert sich jetzt jeden Tag automatisch mit dem aktuellen NASA-APOD-Bild.

Willkommen beim NASA-Powershell-Hacking.
