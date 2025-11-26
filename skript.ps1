param(
    [switch]$Scheduled,   # Wird von der Aufgabenplanung gesetzt: kein Setup, keine Rueckfragen
    [switch]$ForceSetup   # Optional: Setup erzwingen, z.B. wenn du etwas aendern willst
)

# ---------------------------------------------------------
# Optional: Adminrechte holen (nur bei manuellem Start)
# ---------------------------------------------------------
# Idee:
# - Viele Operationen auf der Aufgabenplanung (Register-ScheduledTask)
#   funktionieren zuverlaessiger mit Adminrechten.
# - Wenn das Skript NICHT als Admin laeuft und NICHT aus der Aufgabenplanung
#   gestartet wurde, wird dem Benutzer angeboten, sich per UAC-Prompt
#   einmalig Adminrechte zu holen.

if (-not $Scheduled) {
    # Aktuelle Windows-Identitaet ermitteln
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    # Principal-Objekt fuer Rollenabfrage (z.B. Administrator)
    $principal       = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    # Pruefen, ob aktuelle Identitaet Administrator-Rechte hat
    $isAdmin         = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        # Hinweis fuer den Benutzer
        Write-Host 'Dieses Skript kann die geplante Aufgabe zuverlaessiger einrichten, wenn es mit Administratorrechten laeuft.' -ForegroundColor Yellow
        $answer = Read-Host 'Jetzt mit Adminrechten neu starten? (J/N, Standard: J)'

        # Standard: J, wenn leer
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[JjYy]') {
            # Neuen Prozess vorbereiten, der PowerShell mit "runas" (UAC) startet
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName  = 'powershell.exe'
            # Aktuelles Skript erneut starten, mit Bypass und ohne Profil
            $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
            if ($ForceSetup) {
                # Falls der Benutzer urspruenglich mit -ForceSetup gestartet hat,
                # Parameter beim Neustart beibehalten
                $psi.Arguments += ' -ForceSetup'
            }
            # "runas" sorgt fuer den UAC-Dialog
            $psi.Verb = 'runas'
            try {
                [System.Diagnostics.Process]::Start($psi) | Out-Null
            } catch {
                Write-Host 'Start mit Adminrechten wurde abgebrochen oder ist fehlgeschlagen.' -ForegroundColor Red
            }
            # Aktuelle (nicht-Admin) Instanz beenden
            exit
        }
    }
}

# ---------------------------------------------------------
# Grundkonstanten & Pfade
# ---------------------------------------------------------

# Anzeigename der geplanten Aufgabe
$TaskName   = 'NASA APOD Wallpaper'

# Vollstaendiger Pfad zu diesem Skript (wichtig fuer den Task)
$ScriptPath = $MyInvocation.MyCommand.Path

# Config-Datei liegt im gleichen Verzeichnis wie das Skript
$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath 'nasa_apod_config.json'

# Standard-Zielordner fuer heruntergeladene Bilder (Desktop\NasaBilder)
$DefaultTargetFolder = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop\NasaBilder'

# Standardzeit fuer den taeglichen Task-Lauf (als String im Format HH:mm)
$DefaultRunTime = '08:00'


# ---------------------------------------------------------
# Hilfsfunktionen: Config laden & speichern
# ---------------------------------------------------------
# Die Config-Datei haelt:
# - ApiKey       : NASA-API-Schluessel
# - TargetFolder : Zielverzeichnis fuer die Bilder
# - RunTime      : Gewuenschte Uhrzeit fuer den Task (derzeit rein informativ)
# - TaskCreated  : Ob das Skript bereits versucht hat, einen Task anzulegen

function Load-Config {
    if (Test-Path $ConfigFile) {
        try {
            # JSON-Konfiguration als String einlesen
            $json = Get-Content -Path $ConfigFile -Raw -ErrorAction Stop
            # In PowerShell-Objekt umwandeln
            $cfg  = $json | ConvertFrom-Json -ErrorAction Stop
            return $cfg
        } catch {
            # Bei Fehlern wird eine neue Standard-Config erzeugt
        }
    }

    # Standardconfig zurueckgeben, wenn keine Datei vorhanden ist oder diese defekt war
    return [pscustomobject]@{
        ApiKey      = ''
        TargetFolder= $DefaultTargetFolder
        RunTime     = $DefaultRunTime
        TaskCreated = $false
    }
}

function Save-Config($cfg) {
    # Objekt als JSON auf die Platte schreiben (UTF-8)
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFile -Encoding UTF8
}


# ---------------------------------------------------------
# Scheduled Task anlegen
# ---------------------------------------------------------
# Aufgabe:
# - Pruefen, ob ein Task mit dem gegebenen Namen existiert
# - Falls nein, Benutzer fragen und ggf. taeglichen Task einrichten,
#   der dieses Skript mit Parameter -Scheduled ausfuehrt.

function Ensure-ScheduledTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$RunTime
    )

    # Wenn wir bereits aus der Aufgabenplanung laufen, darf hier KEINE Interaktion stattfinden
    if ($Scheduled) {
        return $false
    }

    # ScheduledTasks-Modul nur nutzen, wenn vorhanden (ab Windows 8 typisch)
    $module = Get-Module -ListAvailable -Name ScheduledTasks
    if (-not $module) {
        Write-Host "Hinweis: Modul 'ScheduledTasks' nicht verfuegbar. Task kann nicht automatisch angelegt werden." -ForegroundColor Yellow
        return $false
    }

    Import-Module ScheduledTasks -ErrorAction SilentlyContinue

    # Existiert die Aufgabe bereits?
    try {
        $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        if ($existing) {
            # Bereits vorhanden -> nichts zu tun
            return $true
        }
    } catch {
        # Kein bestehender Task -> weiter unten neu anlegen
    }

    Write-Host ''
    Write-Host "Noch keine geplante Aufgabe '$TaskName' gefunden." -ForegroundColor Cyan

    # Benutzer fragen, ob eine taegliche Aufgabe erstellt werden soll
    $answer = Read-Host 'Automatisch eine taegliche Aufgabe anlegen? (J/N, Standard: J)'
    if ([string]::IsNullOrWhiteSpace($answer)) {
        $answer = 'J'
    }

    if ($answer -notmatch '^[JjYy]') {
        Write-Host 'Okay, keine geplante Aufgabe angelegt. Skript laeuft nur manuell.' -ForegroundColor Yellow
        return $false
    }

    # Uhrzeit fuer taeglichen Lauf abfragen
    $timePrompt = "Uhrzeit fuer taeglichen Lauf? (HH:mm, Standard: $DefaultRunTime)"
    $timeString = Read-Host $timePrompt
    if ([string]::IsNullOrWhiteSpace($timeString)) {
        $timeString = $DefaultRunTime
    }

    try {
        # Validierung der Eingabe als Zeit im Format HH:mm
        $time = [DateTime]::ParseExact($timeString, "HH:mm", $null)
    } catch {
        # Fallback: Standardzeit verwenden
        Write-Host "Zeitformat nicht erkannt, verwende $DefaultRunTime." -ForegroundColor Yellow
        $time = [datetime]::Today.AddHours(8)
        $timeString = $DefaultRunTime
    }

    # Aktion fuer die Aufgabenplanung:
    # - PowerShell ohne Profil, mit ExecutionPolicy Bypass
    # - dieses Skript (ScriptPath) als -File, plus -Scheduled
    #   ScriptPath wird in Anfuehrungszeichen gesetzt, damit auch Ordner mit Leerzeichen funktionieren.
    $argument = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Scheduled' -f $ScriptPath)
    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument

    # Trigger: taeglich zur angegebenen Uhrzeit
    $trigger  = New-ScheduledTaskTrigger -Daily -At $time

    try {
        # Aufgabe registrieren
        Register-ScheduledTask `
            -TaskName    $TaskName `
            -Action      $action `
            -Trigger     $trigger `
            -Description 'Laedt das NASA Astronomy Picture of the Day und setzt es als Desktop-Hintergrund.'

        Write-Host "Geplante Aufgabe '$TaskName' wurde angelegt (taeglich um $($time.ToString('HH:mm')))." -ForegroundColor Green
        return $true
    } catch {
        # Fehler bei der Registrierung (z.B. fehlende Rechte)
        Write-Host 'Konnte die geplante Aufgabe nicht anlegen:' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host 'Tipp: PowerShell als Administrator starten und Skript erneut ausfuehren.' -ForegroundColor Yellow
        return $false
    }
}


# ---------------------------------------------------------
# Interaktives Setup (nur bei Bedarf)
# ---------------------------------------------------------
# Ablauf:
# - API-Key aus Config oder ENV uebernehmen, sonst abfragen
# - Zielordner anzeigen und ggf. anpassen lassen
# - Optional geplante Aufgabe einrichten

function Run-Setup([ref]$cfgRef) {
    $cfg = $cfgRef.Value

    Write-Host ''
    Write-Host 'NASA APOD Wallpaper - Ersteinrichtung' -ForegroundColor Cyan
    Write-Host '-------------------------------------'

    # API-Key aus Umgebungsvariable übernehmen, falls gesetzt und Config leer
    if ([string]::IsNullOrWhiteSpace($cfg.ApiKey) -and $env:NASA_API_KEY) {
        $cfg.ApiKey = $env:NASA_API_KEY
        Write-Host 'NASA_API_KEY aus Umgebungsvariable gefunden und uebernommen.' -ForegroundColor Green
    }

    # Wenn immer noch kein API-Schluessel vorhanden ist, Benutzer fragen
    if ([string]::IsNullOrWhiteSpace($cfg.ApiKey)) {
        Write-Host ''
        Write-Host 'API-Schluessel benoetigt.' -ForegroundColor Yellow
        Write-Host 'Du bekommst ihn kostenlos unter: https://api.nasa.gov/' -ForegroundColor DarkGray
        $key = Read-Host 'Bitte NASA API-Key eingeben (oder leer lassen zum Abbrechen)'
        if ([string]::IsNullOrWhiteSpace($key)) {
            Write-Host 'Kein API-Key eingegeben. Abbruch.' -ForegroundColor Red
            exit 1
        }
        $cfg.ApiKey = $key
    }

    # Aktuellen Zielordner anzeigen und bei Bedarf anpassen
    Write-Host ''
    Write-Host 'Aktueller Zielordner fuer Bilder:' -ForegroundColor Cyan
    Write-Host "  $($cfg.TargetFolder)" -ForegroundColor White
    $folderInput = Read-Host 'Enter fuer Standard lassen oder neuen Pfad eingeben'
    if (-not [string]::IsNullOrWhiteSpace($folderInput)) {
        $cfg.TargetFolder = $folderInput.Trim()
    }

    # Optional: geplante Aufgabe anlegen
    $taskCreated = Ensure-ScheduledTask -TaskName $TaskName -ScriptPath $ScriptPath -RunTime $cfg.RunTime
    if ($taskCreated) {
        $cfg.TaskCreated = $true
    }

    # Aenderungen an den Aufrufer zurueckgeben
    $cfgRef.Value = $cfg
}


# ---------------------------------------------------------
# APOD holen & Wallpaper setzen
# ---------------------------------------------------------
# Funktion:
# - NASA APOD API mit dem gegebenen ApiKey aufrufen
# - Nur "image"-Antworten verarbeiten (Videos werden uebersprungen)
# - Bild im TargetFolder speichern (Dateiname: yyyy-MM-dd - Titel.jpg)
# - Windows-Desktop-Hintergrund auf dieses Bild setzen

function Set-NasaApodWallpaper {
    param(
        [string]$ApiKey,
        [string]$TargetFolder
    )

    # Ohne API-Key kann kein Abruf erfolgen
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        # Im Scheduled-Modus silently exit
        if ($Scheduled) { return }
        Write-Host 'Kein NASA API-Key konfiguriert.' -ForegroundColor Red
        return
    }

    # Zielordner sicherstellen
    if (-not (Test-Path $TargetFolder)) {
        New-Item -ItemType Directory -Path $TargetFolder | Out-Null
    }

    # API-URL mit Key zusammensetzen
    $apiUrl = "https://api.nasa.gov/planetary/apod?api_key=$ApiKey"

    try {
        # APOD-Daten abrufen (Invoke-RestMethod gibt direkt ein Objekt zurueck)
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop

        # Falls es heute ein Video ist, wird nichts gemacht
        if ($response.media_type -ne 'image') {
            return
        }

        # Titel auf Dateisystem-sichere Zeichen reduzieren
        $title = $response.title -replace '[\\/:*?"<>|]', ''
        # Datum im Format yyyy-MM-dd
        $date  = Get-Date -Format "yyyy-MM-dd"
        # Dateiname inklusive Datum und Titel
        $fileName = "$date - $title.jpg"
        # Vollstaendiger Pfad zur Bilddatei
        $filePath = Join-Path -Path $TargetFolder -ChildPath $fileName

        # Bild nur herunterladen, wenn es noch nicht existiert (z.B. Mehrfachlauf an einem Tag)
        if (-not (Test-Path $filePath)) {
            # hdurl bevorzugen, sonst url
            $imageUrl = if ($response.hdurl) { $response.hdurl } else { $response.url }
            Invoke-WebRequest -Uri $imageUrl -OutFile $filePath -ErrorAction Stop
        }

        # C#-Code als Here-String: kapselt den Aufruf von SystemParametersInfo,
        # um das Hintergrundbild zu setzen.
        $code = @'
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    private static extern int SystemParametersInfo (int uAction, int uParam, string lpvParam, int fuWinIni);
    public static void Set(string path) {
        SystemParametersInfo(20, 0, path, 0x01 | 0x02);
    }
}
'@

        # C#-Typ zur Laufzeit hinzufuegen (nur einmal pro Session notwendig)
        Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
        # Statische Methode aufrufen, um das Wallpaper zu setzen
        [Wallpaper]::Set($filePath)

        # Im manuellen Modus kurze Erfolgsmeldung ausgeben
        if (-not $Scheduled) {
            Write-Host 'Neues Wallpaper gesetzt:' -ForegroundColor Green
            Write-Host "  $filePath" -ForegroundColor White
        }

    } catch {
        # Im geplanten Task laeuft alles still; im manuellen Modus kurze Fehlerinfo
        if (-not $Scheduled) {
            Write-Host 'Fehler beim Abruf oder Setzen des Hintergrunds:' -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor DarkRed
        }
    }
}


# ---------------------------------------------------------
# HAUPTLOGIK
# ---------------------------------------------------------

# Konfiguration laden (bestehende Datei oder Standardwerte)
$config = Load-Config

# Falls explizit -ForceSetup angegeben wurde (nur im manuellen Modus)
if ($ForceSetup -and -not $Scheduled) {
    Run-Setup -cfgRef ([ref]$config)
    Save-Config -cfg $config
}

# Fall 1: Noch kein API-Key vorhanden
if ([string]::IsNullOrWhiteSpace($config.ApiKey)) {
    if (-not $Scheduled) {
        # Im interaktiven Modus Setup anstossen
        Run-Setup -cfgRef ([ref]$config)
        Save-Config -cfg $config
    } else {
        # Im Task-Lauf ohne Key einfach still beenden
        return
    }
} else {
    # Fall 2: API-Key vorhanden, aber laut Config noch kein Task angelegt
    if (-not $config.TaskCreated -and -not $Scheduled) {
        $taskCreated = Ensure-ScheduledTask -TaskName $TaskName -ScriptPath $ScriptPath -RunTime $config.RunTime
        if ($taskCreated) {
            $config.TaskCreated = $true
            Save-Config -cfg $config
        }
    }
}

# APOD abrufen und Wallpaper setzen (funktioniert in beiden Modi)
Set-NasaApodWallpaper -ApiKey $config.ApiKey -TargetFolder $config.TargetFolder
