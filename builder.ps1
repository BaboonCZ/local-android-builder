# ==============================================================================
# AUTOMATICKÁ DETEKCE CESTY, KONTROLA PRÁV ADMINISTRAČNÍHO REŽIMU A PATH
# ==============================================================================
function Test-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[INFO] This action requires administrator privileges. Requesting elevation..." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`" $args" -Verb RunAs
        exit
    }
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = Get-Location }
Set-Location $scriptDir

function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    $winAppsPath = Get-ChildItem "$env:SystemDrive\Users\*\AppData\Local\Microsoft\WindowsApps" -ErrorAction SilentlyContinue | 
                   Where-Object { Test-Path (Join-Path $_.FullName "winget.exe") } | 
                   Select-Object -First 1 -ExpandProperty FullName

    $env:Path = "$machinePath;$userPath;$winAppsPath"
}

function Get-CodeCliPath {
    Update-SessionPath
    $codeCli = Get-Command "code" -ErrorAction SilentlyContinue
    if ($codeCli) { return "code" }

    $knownPaths = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "C:\Program Files\Microsoft VS Code\bin\code.cmd",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "C:\Program Files\Microsoft VS Code\Code.exe"
    )
    return ($knownPaths | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

# --- REGISTRACE DO PROSTŘEDÍ WINDOWS (PATH) ---
function Register-InWindowsPath {
    param ([string]$DirToRegister)

    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $pathParts = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($pathParts -notcontains $DirToRegister) {
        $newPath = ($pathParts + $DirToRegister) -join ';'
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path += ";$DirToRegister"
        Write-Host "[SYSTEM] Directory successfully added to User PATH: $DirToRegister" -ForegroundColor Green
    }

    $cmdAliasPath = Join-Path $DirToRegister "builder.cmd"
    $psScriptPath = Join-Path $DirToRegister "builder.ps1"
    
    $cmdContent = "@echo off`r`npowershell -ExecutionPolicy Bypass -NoProfile -File `"$psScriptPath`""
    if (-not (Test-Path $cmdAliasPath) -or (Get-Content $cmdAliasPath -Raw) -ne $cmdContent) {
        [System.IO.File]::WriteAllText($cmdAliasPath, $cmdContent)
        Write-Host "[SYSTEM] Launch script 'builder.cmd' created." -ForegroundColor Yellow
    }
}

Register-InWindowsPath -DirToRegister $scriptDir

$projectsRoot = $scriptDir
$iniPath = Join-Path $scriptDir "builder.ini"
$templatesDir = Join-Path $scriptDir ".templates"
$expoTemplateDir = Join-Path $templatesDir "expo"
$nodejsTemplateDir = Join-Path $templatesDir "nodejs"
$templateJson = Join-Path $expoTemplateDir "app.json"
$selfScriptPath = Join-Path $scriptDir "builder.ps1"

# --- PAMĚŤ POZIC V MENU ---
$global:mainMenuIndex = 0
$global:configMenuIndex = 0
$global:projectMenuIndex = 3
$global:wizardMenuIndex = 0
$global:sftpMenuIndex = 0

# --- LOKALIZAČNÍ SLOVNÍK (EN / CZ / DE) ---
function Get-Text {
    param ([string]$Key, [string]$Lang = "EN")
    
    $dict = @{
        EN = @{
            SelectProject = "SELECT PROJECT"
            CreateNew     = "[+] CREATE NEW PROJECT"
            RestoreBackup = "[R] RESTORE PROJECT FROM BACKUP (ZIP)"
            Settings      = "[S] BUILDER SETTINGS"
            Exit          = "[X] EXIT BUILDER"
            DevNick       = "Developer Nickname"
            LangSelect    = "Language"
            OpenJson      = "Open app.json"
            OpenTsx       = "Open App.tsx"
            OpenJs        = "Open App.js"
            OpenIndex     = "Open index.js"
            TargetPath    = "APK Output Target Path"
            Back          = "<-- BACK TO MENU"
            PressKey      = "Press any key to continue..."
            
            # Akce projektu
            Act1 = "Open configured files in Notepad++"
            Act2 = "Install Expo/NPM packages"
            Act3 = "Start Expo Go dev server (npx expo start -c)"
            Act4 = "Fast incremental build (Changes -> APK)"
            Act5 = "Clean regen & build (Prebuild --clean -> APK)"
            Act6 = "Update & fix dependencies (Expo install --fix)"
            Act7 = "Check & diagnostics (Expo Doctor)"
            ActBackup = "Create ZIP backup (manifest + assets + src)"
            ActDel = "Delete project"
            ActBack = "<-- BACK TO PROJECT LIST"
            
            # Průvodce a stavy
            SetupWizTitle = "ENVIRONMENT SETUP WIZARD (SYSTEM STATUS)"
            CheckingWinget = "Checking online package versions via Winget..."
            Installed = "[ INSTALLED ]"
            NotInstalled = "[ NOT INSTALLED ]"
            MissingMod = "[ MISSING MODULE ]"
            BadVer = "[ MISSING OR WRONG VERSION! ]"
            RunAutoInstall = "[>>>] RUN AUTOMATIC INSTALLATION OF MISSING APPS [<<<]"
            RunAutoEnv = "[A] AUTOMATICALLY CONFIGURE WINDOWS ENV (JAVA_HOME & ANDROID_HOME)"
            WizBack = "<-- BACK TO SETTINGS"
            ActCleanCache = "Clean cache & temporary files (Metro, Android, Node)"
            CleanCacheTitle = "=== CLEANING CACHE & TEMPORARY FILES ==="
            CleanCacheSuccess = "[OK] Temporary files and caches successfully cleaned!"
            
            # Hlášky a výzvy
            EnterProjName = "Enter project name (or press Enter to cancel)"
            ProjExists = "Project with this name already exists!"
            CreatingProj = "=== Creating new project: "
            ProjSuccess = "DONE! Project created."
            ProjFailed = "Project creation failed."
            WorkingOn = "Working on project:"
            OpenNpp = "=== Opening selected files in Notepad++ ==="
            InstallBasic = "[>>> INSTALL ALL BASIC PACKAGES <<<]"
            InstallCustom = "[+] ENTER CUSTOM PACKAGE MANUALLY"
            EnterPkg = "Package name"
            StartExpo = "=== Starting Expo Go dev server (-c) ==="
            FastBuild = "=== Fast incremental build ==="
            CleanRegen = "=== Clean Regen (Expo Prebuild Clean) ==="
            KillJava = "=== Killing Java processes ==="
            BuildFail = "Build failed with exit code:"
            ApkSaved = "DONE! APK successfully saved to:"
            ApkNotFound = "APK file not found at:"
            BackupTitle = "=== CREATING ZIP BACKUP ==="
            BackupSuccess = "[OK] Backup created:"
            BackupFail = "[ERROR] Error during backup:"
            DelTitle = "=== DELETING PROJECT ==="
            DelNoBackup = "[WARNING] NO BACKUP FOUND for the project in .backup folder! If deleted, source files are lost."
            DelFound = "[INFO] Backup found for the project in .backup folder."
            DelConfirm = "Are you sure you want to delete project"
            DelSuccess = "Project deleted."
            RestNoBackup = "No backups found in '.backup' folder."
            RestMenu = "SELECT ZIP BACKUP TO RESTORE (.backup)"
            RestExistWarning = "Project already exists!"
            RestOverwrite = "Do you want to overwrite/update the existing folder? (Y/N)"
            RestSuccess = "[DONE] Project successfully restored!"
            KeystorePath = "Play Store Keystore Path"
            ActAabBuild = "Build App Bundle for Play Store (.aab)"
            SFTPupload = "Upload on SFTP"
        }
        CZ = @{
            SelectProject = "VÝBĚR PROJEKTU"
            CreateNew     = "[+] VYTVOŘIT NOVÝ PROJEKT"
            RestoreBackup = "[R] OBNOVIT PROJEKT ZE ZÁLOHY (ZIP)"
            Settings      = "[S] NASTAVENÍ BUILDERU"
            Exit          = "[X] UKONČIT BUILDER"
            DevNick       = "Jméno vývojáře (Nick)"
            LangSelect    = "Jazyk (Language)"
            OpenJson      = "Otevírat app.json"
            OpenTsx       = "Otevírat App.tsx"
            OpenJs        = "Otevírat App.js"
            OpenIndex     = "Otevírat index.js"
            TargetPath    = "Cílová složka APK"
            Back          = "<-- ZPĚT DO MENU"
            PressKey      = "Stiskni libovolnou klávesu..."
            
            Act1 = "Otevřít nastavené soubory v Notepad++"
            Act2 = "Instalovat Expo/NPM balíčky"
            Act3 = "Spustit Expo Go dev server (npx expo start -c)"
            Act4 = "Rychlý inkrementální build (Kompilace změn -> APK)"
            Act5 = "Čistý regen a build (Prebuild --clean -> APK)"
            Act6 = "Aktualizace a oprava závislostí (Expo install --fix)"
            Act7 = "Kontrola a diagnostika projektu (Expo Doctor)"
            ActBackup = "Vytvořit ZIP zálohu projektu (manifest + assets + src)"
            ActDel = "Smazat projekt"
            ActBack = "<-- ZPĚT DO NABÍDKY PROJEKTŮ"
            
            SetupWizTitle = "PRŮVODCE INSTALACÍ PROSTŘEDÍ (STAV SYSTÉMU)"
            CheckingWinget = "Kontroluji online verze v wingetu..."
            Installed = "[ NAINSTALOVÁNO ]"
            NotInstalled = "[ NENAINSTALOVÁNO ]"
            MissingMod = "[ CHYBÍ MODUL ]"
            BadVer = "[ CHYBÍ NEBO ŠPATNÁ VERZE! ]"
            RunAutoInstall = "[>>>] SPUSTIT AUTOMATICKOU INSTALACI CHYBĚJÍCÍCH APLIKACÍ [<<<]"
            RunAutoEnv = "[A] AUTOMATICKY KONFIGUROVAT PROSTŘEDÍ WINDOWS (JAVA_HOME & ANDROID_HOME)"
            WizBack = "<-- ZPĚT DO NASTAVENÍ"
            KeystorePath = "cesta ke klíči obchodu Play"
            ActAabBuild = "Vytvořit Build pro Obchod Play (.aab)"
            
            ActCleanCache = "Čištění mezipaměti a dočasných souborů (Metro, Android, Node)"
            CleanCacheTitle = "=== ČIŠTĚNÍ MEZIPAMĚTI A DOČASTNÝCH SOUBORŮ ==="
            CleanCacheSuccess = "[HOTOVO] Dočasné soubory a mezipaměť byly úspěšně vyčištěny!"
            EnterProjName = "Zadej název projektu (nebo stiskni Enter pro storno)"
            ProjExists = "Projekt s tímto názvem už ve složce existuje!"
            CreatingProj = "=== Zakládám nový projekt: "
            ProjSuccess = "HOTOVO! Projekt byl vytvořen."
            ProjFailed = "Vytvoření projektu selhalo."
            WorkingOn = "Pracuji na projektu:"
            OpenNpp = "=== Otevírám vybrané soubory v Notepad++ ==="
            InstallBasic = "[>>> INSTALOVAT VŠECHNY ZÁKLADNÍ BALÍČKY <<<]"
            InstallCustom = "[+] ZADAT VLASTNÍ BALÍČEK RUČNĚ"
            EnterPkg = "Název balíčku"
            StartExpo = "=== Spouštím Expo Go dev server (-c) ==="
            FastBuild = "=== Rychlý inkrementální build ==="
            CleanRegen = "=== Čistý Regen (Expo Prebuild Clean) ==="
            KillJava = "=== Ukončování procesů Java ==="
            BuildFail = "Build selhal s chybovým kódem:"
            ApkSaved = "HOTOVO! APK bylo úspěšně uloženo do:"
            ApkNotFound = "Soubor APK nebyl nalezen na cestě:"
            BackupTitle = "=== VYTVOŘENÍ ZIP ZÁLOHY ==="
            BackupSuccess = "[OK] Záloha byla úspěšně vytvořena:"
            BackupFail = "[CHYBA] Při zálohování došlo k chybě:"
            DelTitle = "=== SMAZÁNÍ PROJEKTU ==="
            DelNoBackup = "[VAROVÁNÍ] Pro projekt NEBYLA NALEZENA ŽÁDNÁ ZÁLOHA ve složce .backup! Přijdete o zdrojové kódy."
            DelFound = "[INFO] Pro projekt byla nalezena záloha ve složce .backup."
            DelConfirm = "Opravdu chceš smazat projekt"
            DelSuccess = "Projekt byl smazán."
            RestNoBackup = "Ve složce '.backup' nebyly nalezeny žádné ZIP zálohy."
            RestMenu = "VYBER ZIP ZÁLOHU K OBNOVĚ (.backup)"
            RestExistWarning = "Projekt již na cestě existuje!"
            RestOverwrite = "Chceš existující složku přepsat/aktualizovat? (A/N)"
            RestSuccess = "[HOTOVO] Projekt byl úspěšně obnoven!"
            SFTPupload = "Nahrávat na SFTP"
        }
        DE = @{
            SelectProject = "PROJEKT AUSWÄHLEN"
            CreateNew     = "[+] NEUES PROJEKT ERSTELLEN"
            RestoreBackup = "[R] PROJEKT AUS BACKUP WIEDERHERSTELLEN (ZIP)"
            Settings      = "[S] BUILDER-EINSTELLUNGEN"
            Exit          = "[X] BUILDER BEENDEN"
            DevNick       = "Entwickler-Name (Nick)"
            LangSelect    = "Sprache (Language)"
            OpenJson      = "app.json öffnen"
            OpenTsx       = "App.tsx öffnen"
            OpenJs        = "App.js öffnen"
            OpenIndex     = "index.js öffnen"
            TargetPath    = "APK-Zielpfad"
            Back          = "<-- ZURÜCK ZUM MENÜ"
            PressKey      = "Drücken Sie eine beliebige Taste..."
            
            Act1 = "Konfigurierte Dateien in Notepad++ öffnen"
            Act2 = "Expo/NPM Pakete installieren"
            Act3 = "Expo Go Dev-Server starten (npx expo start -c)"
            Act4 = "Schneller inkrementeller Build (Änderungen -> APK)"
            Act5 = "Sauberer Regen & Build (Prebuild --clean -> APK)"
            Act6 = "Abhängigkeiten aktualisieren & reparieren (Expo install --fix)"
            Act7 = "Projektprüfung & Diagnose (Expo Doctor)"
            ActBackup = "ZIP-Backup erstellen (manifest + assets + src)"
            ActDel = "Projekt löschen"
            ActBack = "<-- ZURÜCK ZUR PROJEKTLISTE"
            
            ActCleanCache = "Cache & temporäre Dateien bereinigen (Metro, Android, Node)"
            CleanCacheTitle = "=== BEREINIGUNG VON CACHE UND TEMPORÄREN DATEIEN ==="
            CleanCacheSuccess = "[FERTIG] Temporäre Dateien und Cache erfolgreich bereinigt!"
            SetupWizTitle = "UMGEBUNGS-SETUP (SYSTEMSTATUS)"
            CheckingWinget = "Online-Paketversionen werden über Winget geprüft..."
            Installed = "[ INSTALLIERT ]"
            NotInstalled = "[ NICHT INSTALLIERT ]"
            MissingMod = "[ FEHLENDES MODUL ]"
            BadVer = "[ FEHLT ODER FALSCHE VERSION! ]"
            RunAutoInstall = "[>>>] AUTOMATISCHE INSTALLATION FEHLENDER APPS STARTEN [<<<]"
            RunAutoEnv = "[A] WINDOWS-UMGEBUNG AUTOMATISCH KONFIGURIEREN (JAVA_HOME & ANDROID_HOME)"
            WizBack = "<-- ZURÜCK ZU EINSTELLUNGEN"
            KeystorePath = "Play Store Keystore-Pfad"
            ActAabBuild = "App Bundle für Play Store erstellen (.aab)"
            
            EnterProjName = "Geben Sie den Projektnamen ein (oder Enter zum Abbrechen)"
            ProjExists = "Ein Projekt mit diesem Namen existiert bereits!"
            CreatingProj = "=== Erstelle neues Projekt: "
            ProjSuccess = "FERTIG! Projekt erstellt."
            ProjFailed = "Projekterstellung fehlgeschlagen."
            WorkingOn = "Arbeite an Projekt:"
            OpenNpp = "=== Öffne ausgewählte Dateien in Notepad++ ==="
            InstallBasic = "[>>> ALLE BASISPAKETE INSTALLIEREN <<<]"
            InstallCustom = "[+] BENUTZERDEFINIERTES PAKET MANUELL EINGEBEN"
            EnterPkg = "Paketname"
            StartExpo = "=== Starte Expo Go Dev-Server (-c) ==="
            FastBuild = "=== Schneller inkrementeller Build ==="
            CleanRegen = "=== Sauberer Regen (Expo Prebuild Clean) ==="
            KillJava = "=== Beende Java-Prozesse ==="
            BuildFail = "Build fehlgeschlagen mit Fehlercode:"
            ApkSaved = "FERTIG! APK erfolgreich gespeichert unter:"
            ApkNotFound = "APK-Datei nicht gefunden unter:"
            BackupTitle = "=== ZIP-BACKUP ERSTELLEN ==="
            BackupSuccess = "[OK] Backup erfolgreich erstellt:"
            BackupFail = "[FEHLER] Fehler beim Sichern:"
            DelTitle = "=== PROJEKT LÖSCHEN ==="
            DelNoBackup = "[WARNUNG] KEIN BACKUP für dieses Projekt in .backup gefunden! Quelldateien gehen verloren."
            DelFound = "[INFO] Backup für das Projekt im .backup-Ordner gefunden."
            DelConfirm = "Möchten Sie das Projekt wirklich löschen"
            DelSuccess = "Projekt gelöscht."
            RestNoBackup = "Keine ZIP-Backups im Ordner '.backup' gefunden."
            RestMenu = "ZIP-BACKUP ZUR WIEDERHERSTELLUNG WÄHLEN (.backup)"
            RestExistWarning = "Das Projekt existiert bereits!"
            RestOverwrite = "Möchten Sie den vorhandenen Ordner überschreiben/aktualisieren? (J/N)"
            RestSuccess = "[FERTIG] Projekt erfolgreich wiederhergestellt!"
            SFTPupload = "Auf SFTP hochladen"
        }
    }

    if ($dict[$Lang] -and $dict[$Lang][$Key]) { return $dict[$Lang][$Key] }
    if ($dict["EN"][$Key]) { return $dict["EN"][$Key] }
    return $Key
}

# --- NAČÍTÁNÍ & PRŮVODCE KONFIGURACE ---
function Get-Config {
    $config = @{
        Language    = ""
        Nick        = ""
        OpenAppJson = $true
        OpenAppTsx  = $true
        OpenAppJs   = $false
        OpenIndexJs = $false
        uploadSFTP = $false
        TargetPath  = (Join-Path $scriptDir "_Android_App")
    }

    $iniExists = Test-Path $iniPath
    if ($iniExists) {
        $lines = Get-Content $iniPath
        foreach ($line in $lines) {
            if ($line -match '^\s*([^=]+)\s*=\s*(.*)\s*$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim()
                if ($val -eq 'True') { $config[$key] = $true }
                elseif ($val -eq 'False') { $config[$key] = $false }
                else { $config[$key] = $val }
            }
        }
    }

    $needsSave = -not $iniExists

    # 1. Dotaz na JAZYK (pokud chybí)
    if ([string]::IsNullOrWhiteSpace($config.Language)) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  LANGUAGE SELECTION" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "1) English (EN)"
        Write-Host "2) Deutsch (DE)"
        Write-Host "3) Čeština (CZ)`n"
        
        $langChoice = Read-Host "Select language [Default: 1]"
        switch ($langChoice.Trim()) {
            "3" { $config.Language = "CZ" }
            "2" { $config.Language = "DE" }
            default { $config.Language = "EN" }
        }
        $needsSave = $true
    }

    # 2. Dotaz na NICK (pokud chybí)
    if ([string]::IsNullOrWhiteSpace($config.Nick)) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        $titleText = switch ($config.Language) {
            "CZ" { "NASTAVENÍ JMÉNA VÝVOJÁŘE" }
            "DE" { "ENTWICKLER-NICKNAME SETUP" }
            default { "DEVELOPER NICKNAME SETUP" }
        }
        $promptMsg = switch ($config.Language) {
            "CZ" { "Zadej jméno vývojáře / Nick (např. BestDeveloper):" }
            "DE" { "Geben Sie Ihren Entwickler-Nickname ein (z. B. BestDeveloper):" }
            default { "Enter developer nickname (e.g. BestDeveloper):" }
        }
        Write-Host "  $titleText" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "$promptMsg`n" -ForegroundColor Gray
        
        $inputNick = Read-Host "Nick"
        if ([string]::IsNullOrWhiteSpace($inputNick)) {
            $config.Nick = "Dev"
        } else {
            $config.Nick = $inputNick.Trim()
        }
        $needsSave = $true
    }

    if ($needsSave) {
        Save-Config $config
    }
    return $config
}

# --- ŠIFROVÁNÍ A DEKÓDOVÁNÍ HESLA PŘES WINDOWS DPAPI ---
function Get-DecryptedPassword {
    param ([string]$EncryptedHash)
    if ([string]::IsNullOrWhiteSpace($EncryptedHash)) { return "" }
    try {
        $securePass = ConvertTo-SecureString $EncryptedHash
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
        $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        return $plainPass
    } catch {
        return ""
    }
}

# --- FUNKCE PRO DEPLOY APK A VERSION.JSON NA SFTP ---
function Publish-ApkToSftp {
    param (
        [string] $ProjectPath,
        [string] $ProjectName,
        [string] $ApkFilePath
    )
    $cfg = Get-Config
    if ([string]::IsNullOrWhiteSpace($cfg.SftpHost) -or [string]::IsNullOrWhiteSpace($cfg.SftpUser)) {
        Write-Host "`n[WARNING] SFTP is not configured in Settings! Skipping deployment." -ForegroundColor Yellow
        return
    }

    $pass = Get-DecryptedPassword $cfg.SftpPassHash
    $appJsonPath = Join-Path $ProjectPath "app.json"
    
    # Načtení dat z app.json
    $ver = "1.0.0"
    $pkgName = "com.dev.$ProjectName"
    $verCode = 1

    if (Test-Path $appJsonPath) {
        try {
            $appConfig = Get-Content $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $appConfig.expo) {
                if ($appConfig.expo.version) { $ver = $appConfig.expo.version.Trim() }
                if ($appConfig.expo.android.package) { $pkgName = $appConfig.expo.android.package.Trim() }
                if ($appConfig.expo.android.versionCode) { $verCode = [int] $appConfig.expo.android.versionCode }
            }
        } catch {}
    }

    $apkFileName = "$($ProjectName)_v$ver.apk"
    $remoteApkUrl = "$($cfg.SftpBaseUrl.TrimEnd('/'))/$apkFileName"

    # 1. Vytvoření souboru version.json
    $versionData = [PSCustomObject]@{
        packageName = $pkgName
        version     = $ver
        versionCode = $verCode
        apkUrl      = $remoteApkUrl
        updatedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    
    $tempVersionPath = Join-Path $env:TEMP "version.json"
    $versionJson = $versionData | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($tempVersionPath, $versionJson, (New-Object System.Text.UTF8Encoding $false))

    # 2. Upload APK a VERSION.JSON přes nativní curl.exe
    Write-Host "`n=== DEPLOYING TO SFTP SERVER ===" -ForegroundColor Cyan
    $baseRemoteUrl = "sftp://$($cfg.SftpHost):$($cfg.SftpPort)$($cfg.SftpRemoteDir.TrimEnd('/'))"

    Write-Host "[1/2] Uploading APK: $apkFileName ..." -ForegroundColor Yellow
    & curl.exe -u "$($cfg.SftpUser):$pass" -T "$ApkFilePath" "$baseRemoteUrl/$apkFileName" --insecure -s

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] APK uploaded successfully." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to upload APK (code $LASTEXITCODE)." -ForegroundColor Red
        return
    }

    Write-Host "[2/2] Uploading version.json ..." -ForegroundColor Yellow
    & curl.exe -u "$($cfg.SftpUser):$pass" -T "$tempVersionPath" "$baseRemoteUrl/version.json" --insecure -s

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] version.json uploaded successfully." -ForegroundColor Green
        Write-Host "`n[SUCCESS] Deployment complete! Remote update URL: $remoteApkUrl" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to upload version.json (code $LASTEXITCODE)." -ForegroundColor Red
    }

    Remove-Item $tempVersionPath -Force -ErrorAction SilentlyContinue
}

function Show-SetupSFTP {
    while ($true) {
        $cfg = Get-Config
        $L = $cfg.Language
        
        $passStatus = if ($cfg.SftpPassHash) { "*****" } else { "[NOT SET]" }
        $hostVal    = if ($cfg.SftpHost) { $cfg.SftpHost } else { "[NOT SET]" }
        $portVal    = if ($cfg.SftpPort) { $cfg.SftpPort } else { "22" }
        $userVal    = if ($cfg.SftpUser) { $cfg.SftpUser } else { "[NOT SET]" }
        $dirVal     = if ($cfg.SftpRemoteDir) { $cfg.SftpRemoteDir } else { "[NOT SET]" }
        $urlVal     = if ($cfg.SftpBaseUrl) { $cfg.SftpBaseUrl } else { "[NOT SET]" }

        $opts = @(
            "SFTP Host:        $hostVal",
            "SFTP Port:        $portVal",
            "SFTP User:        $userVal",
            "SFTP Password:    $passStatus",
            "Remote Directory: $dirVal",
            "Base HTTP URL:    $urlVal",
            "$(Get-Text 'Back' $L)"
        )

        $idx = Show-Menu -Title "SFTP DEPLOYMENT CONFIGURATION" -Options $opts -InitialIndex $global:sftpMenuIndex
        if ($idx -eq -1 -or $idx -eq ($opts.Count - 1)) { return }

        # Uložíme aktuálně zvolený index, aby kurzor zůstal na stejném místě
        $global:sftpMenuIndex = $idx

        Clear-Host
        switch ($idx) {
            0 {
                $inHost = Read-Host "SFTP Host (e.g. sftp.webhosting.com)"
                if (-not [string]::IsNullOrWhiteSpace($inHost)) {
                    $cfg.SftpHost = $inHost.Trim()
                    Save-Config $cfg
                }
            }
            1 {
                $inPort = Read-Host "SFTP Port [Default: 22]"
                if (-not [string]::IsNullOrWhiteSpace($inPort)) {
                    $cfg.SftpPort = $inPort.Trim()
                    Save-Config $cfg
                }
            }
            2 {
                $inUser = Read-Host "SFTP User"
                if (-not [string]::IsNullOrWhiteSpace($inUser)) {
                    $cfg.SftpUser = $inUser.Trim()
                    Save-Config $cfg
                }
            }
            3 {
                $secPass = Read-Host "SFTP Password (masked input)" -AsSecureString
                $bstrPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
                $plainCheck = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrPass)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrPass)

                if (-not [string]::IsNullOrWhiteSpace($plainCheck)) {
                    $cfg.SftpPassHash = ConvertFrom-SecureString $secPass
                    Save-Config $cfg
                    Write-Host "`n[OK] Password encrypted via DPAPI and saved." -ForegroundColor Green
                    Start-Sleep -Seconds 1
                }
            }
            4 {
                $inDir = Read-Host "Remote Directory (e.g. /web/app_folder)"
                if (-not [string]::IsNullOrWhiteSpace($inDir)) {
                    $cfg.SftpRemoteDir = $inDir.Trim()
                    Save-Config $cfg
                }
            }
            5 {
                $inUrl = Read-Host "Base HTTP URL (e.g. https://www.mydomain.com)"
                if (-not [string]::IsNullOrWhiteSpace($inUrl)) {
                    $cfg.SftpBaseUrl = $inUrl.Trim()
                    Save-Config $cfg
                }
            }
        }
    }
}

function Save-Config ($cfg) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($k in $cfg.Keys) {
        [void]$sb.AppendLine("$k = $($cfg[$k])")
    }
    [System.IO.File]::WriteAllText($iniPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
}

# --- DETEKCE TYPU PROJEKTU ---
function Get-ProjectType {
    param ([string]$ProjectPath)

    $projIni = Join-Path $ProjectPath "project.ini"
    if (Test-Path $projIni) {
        $lines = Get-Content $projIni
        foreach ($line in $lines) {
            if ($line -match '^\s*ProjectType\s*=\s*(.*)\s*$') {
                return $matches[1].Trim().ToLower()
            }
        }
    }

    # Fallback detekce pokud project.ini neexistuje
    if (Test-Path (Join-Path $ProjectPath "app.json")) { return "expo" }
    if (Test-Path (Join-Path $ProjectPath "package.json")) { return "nodejs" }

    return "unknown"
}

# --- 1. Inicializace chybějících složek a šablon ---
$currentConfig = Get-Config
$activeNick = if (-not [string]::IsNullOrWhiteSpace($currentConfig.Nick)) { $currentConfig.Nick.Trim() } else { "Dev" }

$expoAssetsDir = Join-Path $expoTemplateDir "assets"
if (-not (Test-Path $expoAssetsDir)) {
    New-Item -ItemType Directory -Path $expoAssetsDir -Force | Out-Null
}

$iconSource = Join-Path $expoAssetsDir "$activeNick.png"

# Zajištění existenci složek pro šablony
if (-not (Test-Path $expoTemplateDir)) {
    New-Item -ItemType Directory -Path $expoTemplateDir -Force | Out-Null
}
if (-not (Test-Path $nodejsTemplateDir)) {
    New-Item -ItemType Directory -Path $nodejsTemplateDir -Force | Out-Null
}

# Vytvoření výchozího app.json přímo v .templates/expo/
if (-not (Test-Path $templateJson)) {
    $defaultAppJson = @"
{
  "expo": {
    "name": "DEFAULT_NAME",
    "slug": "default_slug",
    "version": "1.0.0",
    "orientation": "portrait",
    "icon": "./assets/usernick.png",
    "userInterfaceStyle": "automatic",
    "android": {
      "adaptiveIcon": {
        "backgroundColor": "#121212",
        "foregroundImage": "./assets/usernick.png"
      },
      "package": "com.usernick_low.default"
    }
  }
}
"@
    [System.IO.File]::WriteAllText($templateJson, $defaultAppJson, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "[INIT] Vytvořen základní vzorový soubor .templates/expo/app.json" -ForegroundColor Yellow
}

if (-not (Test-Path $iconSource)) {
    try {
        Add-Type -AssemblyName System.Drawing
        $bmp = New-Object System.Drawing.Bitmap(64, 64)
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.Clear([System.Drawing.Color]::White)
        $gfx.Dispose()
        $bmp.Save($iconSource, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host "[INIT] Vytvořen platný záložní PNG soubor (64x64 px): $activeNick.png" -ForegroundColor Yellow
    } catch {
        [System.IO.File]::WriteAllText($iconSource, "DUMMY PNG")
    }
}

# --- POMOCNÉ FUNKCE ---
function Publish-Apk {
    param (
        [string]$ProjectName,
        [string]$ProjectPath,
        [string]$Lang
    )
    $cfg = Get-Config
    $TargetPath = $cfg.TargetPath

    $apkSource = Join-Path $ProjectPath "android\app\build\outputs\apk\release\app-release.apk"
    if (-not (Test-Path $apkSource)) {
        Write-Host "`n$(Get-Text 'ApkNotFound' $Lang) $apkSource" -ForegroundColor Red
        return
    }

    $appJsonPath = Join-Path $ProjectPath "app.json"
    $ver = "1.0.0"
    $slug = $ProjectName

    if (Test-Path $appJsonPath) {
        try {
            $appConfig = Get-Content $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $appConfig.expo) {
                if (-not [string]::IsNullOrWhiteSpace($appConfig.expo.version)) { $ver = $appConfig.expo.version.Trim() }
                if (-not [string]::IsNullOrWhiteSpace($appConfig.expo.slug)) { $slug = $appConfig.expo.slug.Trim() }
            }
        } catch {}
    }

    if (-not (Test-Path $TargetPath)) { 
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null 
    }

    $destination = Join-Path $TargetPath "$($slug)_v$ver.apk"
    Move-Item $apkSource $destination -Force
    Write-Host "`n$(Get-Text 'ApkSaved' $Lang) $destination" -ForegroundColor Green
}

function Open-InNotepadPlusPlus {
    param (
        [string]$ProjectPath,
        [string]$Lang
    )
    $cfg = Get-Config
    $nppPaths = @(
        "C:\Program Files\Notepad++\notepad++.exe",
        "C:\Program Files (x86)\Notepad++\notepad++.exe"
    )
    $exe = $nppPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $exe) {
        Write-Host "`nNotepad++ is not installed in default paths!" -ForegroundColor Red
        return
    }

    $filesToOpen = @()
    if ($cfg.OpenAppJson -and (Test-Path (Join-Path $ProjectPath "app.json"))) { $filesToOpen += Join-Path $ProjectPath "app.json" }
    if ($cfg.OpenAppTsx -and (Test-Path (Join-Path $ProjectPath "App.tsx"))) { $filesToOpen += Join-Path $ProjectPath "App.tsx" }
    if ($cfg.OpenAppJs -and (Test-Path (Join-Path $ProjectPath "App.js"))) { $filesToOpen += Join-Path $ProjectPath "App.js" }
    if ($cfg.OpenIndexJs -and (Test-Path (Join-Path $ProjectPath "index.js"))) { $filesToOpen += Join-Path $ProjectPath "index.js" }

    if ($filesToOpen.Count -gt 0) {
        Start-Process -FilePath $exe -ArgumentList $filesToOpen
        Write-Host "`n$(Get-Text 'OpenNpp' $Lang)" -ForegroundColor Green
    }
}

function Open-SelfInNotepad {
    $nppPaths = @(
        "C:\Program Files\Notepad++\notepad++.exe",
        "C:\Program Files (x86)\Notepad++\notepad++.exe"
    )
    $exe = $nppPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $exe) { return }

    Write-Host "`n=== OPENING BUILDER.PS1 IN NOTEPAD++ ===" -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList "`"$selfScriptPath`""
}

function Show-Menu {
    param (
        [string]$Title,
        [array]$Options,
        [int]$InitialIndex = 0
    )
    $selectedIndex = $InitialIndex
    if ($selectedIndex -ge $Options.Count -or $selectedIndex -lt 0) {$selectedIndex = 0 }

    try {
        try { $host.ui.RawUI.CursorSize = 0 } catch {}
        while ($true) {
            Clear-Host
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  $Title" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "UP/DOWN arrows, numbers (1-$($Options.Count)) or Enter to select:`n" -ForegroundColor Gray

            for ($i = 0; $i -lt $Options.Count; $i++) {
                if ($i -eq $selectedIndex) {
                    Write-Host " > $($i + 1)) $($Options[$i]) " -ForegroundColor Black -BackgroundColor Cyan
                } else {
                    Write-Host "   $($i + 1)) $($Options[$i]) "
                }
            }

            # Bezpečné načtení stisku klávesy s fallbackem na System.Console
            $vk = 0
            try {
                $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $vk = $key.VirtualKeyCode
            } catch {
                $cKey = [System.Console]::ReadKey($true)
                $vk = [int]$cKey.Key
            }

            if ($vk -eq 38) { # Šipka NAHORU
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = $Options.Count - 1 }
            }
            elseif ($vk -eq 40) { # Šipka DOLŮ
                $selectedIndex++
                if ($selectedIndex -ge $Options.Count) { $selectedIndex = 0 }
            }
            elseif ($vk -eq 13) { # Enter
                return $selectedIndex
            }
            elseif ($vk -eq 27) { # Escape
                return -1
            }
            elseif ($vk -ge 49 -and $vk -le 57) { # Čísla 1-9 (horní řada)
                $numIndex = $vk - 49
                if ($numIndex -lt $Options.Count) { return $numIndex }
            }
            elseif ($vk -ge 97 -and $vk -le 105) { # Čísla 1-9 (Numpad)
                $numIndex = $vk - 97
                if ($numIndex -lt $Options.Count) { return $numIndex }
            }
        }
    }
    catch {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  $Title" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host "  $($i + 1)) $($Options[$i])"
        }
        Write-Host ""
        $inputVal = Read-Host "Select index"
        if ([string]::IsNullOrWhiteSpace($inputVal)) { return -1 }
        $parsed = 0
        if ([int]::TryParse($inputVal.Trim(), [ref]$parsed)) {
            $idx = $parsed - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count) { return $idx }
        }
        return -1
    }
}

# --- POMOCNÁ FUNKCE ČÍSLO AKTUÁLNÍ VERZE Z WINGET ---
function Get-WingetOnlineVersion {
    param([string]$PackageId)
    try {
        $out = winget show --id $PackageId --accept-source-agreements 2>$null | Out-String
        if ($out -match 'Version:\s+([^\r\n]+)') {
            return $matches[1].Trim()
        }
    } catch {}
    return "?"
}


# --- PRŮVODCE INSTALACÍ PROSTŘEDÍ ---
function Show-SetupWizard {
    $cfg = Get-Config
    $L = $cfg.Language
    
    # 1. Načte se pouze jednou při otevření průvodce
    Clear-Host
    Write-Host "$(Get-Text 'CheckingWinget' $L)" -ForegroundColor Cyan
    $nodeOnline = Get-WingetOnlineVersion "OpenJS.NodeJS.LTS"
    $javaOnline = Get-WingetOnlineVersion "EclipseAdoptium.Temurin.17.JDK"
    $asOnline = Get-WingetOnlineVersion "Google.AndroidStudio"
    $nppOnline = Get-WingetOnlineVersion "Notepad++.Notepad++"
    $codeOnline = Get-WingetOnlineVersion "Microsoft.VisualStudioCode"

        while ($true) {
            Update-SessionPath
            Clear-Host

            $nodeVer = try { (node -v 2>$null) } catch { $null }
            if (-not $nodeVer -and (Test-Path "C:\Program Files\nodejs\node.exe")) { $nodeVer = "v18+" }
            $nodeStatus = if (-not $nodeVer) {
                        $(Get-Text 'NotInstalled' $L)
                    } elseif ($nodeOnline -and $nodeOnline -ne "?" -and $nodeVer.TrimStart('v') -ne $nodeOnline.TrimStart('v')) {
                        "[ $nodeVer ] -> NEED UPDATE (v$nodeOnline)"
                    } else {
                        "[ $nodeVer ]"
                    }

            $javaVer = try {$jOut = (java -version 2>&1 | Out-String)
                if ($jOut -match 'version "(17\.[^"]+)"') { "v" + $matches[1] } else { $null }
            } catch { $null }
            
            # Zkrácení na major.minor.patch (např. 17.0.20)
            $jLocalShort  = ($javaVer.TrimStart('v') -split '\.')[0..2] -join '.'
            $jOnlineShort = ($javaOnline.TrimStart('v') -split '\.')[0..2] -join '.'

            $javaStatus = if (-not $javaVer) {
                    $(Get-Text 'NotInstalled' $L)
                } elseif ($javaOnline -and $javaOnline -ne "?" -and $jLocalShort -ne $jOnlineShort) {
                    "[ $javaVer ] -> NEED UPDATE (v$javaOnline)"
                } else {
                    "[ $javaVer ]"
                }

            $asPaths = @(
                "C:\Program Files\Android\Android Studio\bin\studio64.exe",
                "C:\Program Files (x86)\Android\Android Studio\bin\studio64.exe"
            )
            $asExe = $asPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            $asStatus = if ($asExe) { 
            $asRootDir  = (Get-Item $asExe).Directory.Parent.FullName
            $asJsonPath = Join-Path $asRootDir "product-info.json"

            # Vytvoření verze z dataDirectoryName (např. AndroidStudio2026.1.4 -> 2026.1.4)
            $asFvi = if (Test-Path $asJsonPath) {
                $json = Get-Content $asJsonPath -Raw | ConvertFrom-Json
                if ($json.dataDirectoryName -match 'AndroidStudio([\d\.]+)') {
                    $matches[1]
                } else {
                    (Get-Item $asExe).VersionInfo.ProductVersion
                }
            } else {
                (Get-Item $asExe).VersionInfo.ProductVersion
            }

            # Porovnání prvních 3 částí verze (např. 2026.1.4 vs 2026.1.4.7)
            $asLocalShort  = ($asFvi -split '\.')[0..2] -join '.'
            $asOnlineShort = ($asOnline -split '\.')[0..2] -join '.'

                if ($asOnline -and $asOnline -ne "?" -and $asLocalShort -ne $asOnlineShort) {
                    "[ v$asFvi ] -> NEED UPDATE (v$asOnline)"
                } else {
                    "[ v$asFvi ]"
                }
            } else { 
                $(Get-Text 'NotInstalled' $L) 
            }

            $nppPaths = @(
                "C:\Program Files\Notepad++\notepad++.exe",
                "C:\Program Files (x86)\Notepad++\notepad++.exe"
            )
            $nppExe = $nppPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            $nppStatus = if ($nppExe) { 
                $nppFvi = (Get-Item $nppExe).VersionInfo.ProductVersion

                # Porovnání prvních 3 částí verze (např. 8.9.8)
                $nppLocalShort  = ($nppFvi.TrimStart('v') -split '\.')[0..2] -join '.'
                $nppOnlineShort = ($nppOnline.TrimStart('v') -split '\.')[0..2] -join '.'

                if ($nppOnline -and $nppOnline -ne "?" -and $nppLocalShort -ne $nppOnlineShort) {
                    "[ v$nppFvi ] -> NEED UPDATE (v$nppOnline)"
                } else {
                    "[ v$nppFvi ]"
                }
            } else { 
                $(Get-Text 'NotInstalled' $L) 
            }

            $codePaths = @(
                "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
                "C:\Program Files\Microsoft VS Code\Code.exe"
            )
            $codeExe = $codePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            $codeStatus = if ($codeExe) { 
                $codeFvi = (Get-Item $codeExe).VersionInfo.ProductVersion

                # Porovnání major.minor.patch (např. 1.138.0)
                $codeLocalShort  = ($codeFvi.TrimStart('v') -split '\.')[0..2] -join '.'
                $codeOnlineShort = ($codeOnline.TrimStart('v') -split '\.')[0..2] -join '.'

                if ($codeOnline -and $codeOnline -ne "?" -and $codeLocalShort -ne $codeOnlineShort) {
                    "[ v$codeFvi ] -> NEED UPDATE (v$codeOnline)"
                } else {
                    "[ v$codeFvi ]"
                }
            } else { 
                $(Get-Text 'NotInstalled' $L) 
            }

            $hasContinueMod = $false
            $codeCliPath = Get-CodeCliPath
            if ($codeExe -and $codeCliPath) {
                $hasContinueMod = try {
                    $exts = & $codeCliPath --list-extensions 2>$null
                    $exts -contains "continue.continue"
                } catch { $false }
            }
            $aiStatus = if ($hasContinueMod) { $(Get-Text 'Installed' $L) } else { $(Get-Text 'MissingMod' $L) }

            $sdkDefault = "$env:LOCALAPPDATA\Android\Sdk"
            $sdkStatus = if ((Test-Path $sdkDefault) -and (Test-Path (Join-Path $sdkDefault "platform-tools"))) { 
                "[ OK: $sdkDefault ]" 
            } else { 
                $(Get-Text 'NotInstalled' $L)
            }

            $envJava = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
            if (-not $envJava) {$envJava = $env:JAVA_HOME }
            $javaEnvValid = ($envJava -and (Test-Path $envJava) -and ($envJava -match '17'))
            $javaEnvStatus = if ($javaEnvValid) { "[ OK: $envJava ]" } else { $(Get-Text 'BadVer' $L) }

            $envAndroid = [System.Environment]::GetEnvironmentVariable("ANDROID_HOME", "User")
            if (-not $envAndroid) { $envAndroid = $env:ANDROID_HOME }
            $androidEnvValid = ($envAndroid -and (Test-Path $envAndroid) -and (Test-Path (Join-Path $envAndroid "platform-tools")))
            $androidEnvStatus = if ($androidEnvValid) { "[ OK: $envAndroid ]" } else { $(Get-Text 'BadVer' $L) }

            $allAppsInstalled = ($nodeVer -and $javaVer -and $asExe -and $nppExe -and $codeExe -and $hasContinueMod -and (Test-Path $sdkDefault))
            $allEnvValid = ($javaEnvValid -and $androidEnvValid)

            $steps = @()
            $steps += "Node.js:               $nodeStatus"
            $steps += "OpenJDK 17:            $javaStatus"
            $steps += "Android Studio:        $asStatus"
            $steps += "Notepad++:             $nppStatus"
            $steps += "VS Code Editor:        $codeStatus"
            $steps += "VS Code - Continue AI: $aiStatus"
            $steps += "Android SDK:           $sdkStatus"
            $steps += "JAVA_HOME:             $javaEnvStatus"
            $steps += "ANDROID_HOME:          $androidEnvStatus"

            if (-not $allAppsInstalled) { $steps += $(Get-Text 'RunAutoInstall' $L) }

            if (-not $allEnvValid) { $steps += $(Get-Text 'RunAutoEnv' $L) }

            $steps += $(Get-Text 'WizBack' $L)

            $idx = Show-Menu -Title $(Get-Text 'SetupWizTitle' $L) -Options $steps -InitialIndex $global:wizardMenuIndex
            if ($idx -ne -1) { $global:wizardMenuIndex = $idx } else { return }

            $selectedText = $steps[$idx]

            # 1. Ukončení při stisku Esc (-1) nebo volbě tlačítka ZPĚT (vždy poslední položka)
            if ($idx -eq -1 -or $idx -eq ($steps.Count - 1)) {
                return
            }

            # 2. Odbavení pevných pozic (0 až 8) a dynamických akcí
            switch ($idx) {
            0 { # Node.js
                Test-AdminPrivileges
                winget install --id OpenJS.NodeJS.LTS -e --force --accept-package-agreements --accept-source-agreements
                Update-SessionPath
            }
            1 { # OpenJDK 17
                Test-AdminPrivileges
                winget install --id EclipseAdoptium.Temurin.17.JDK -e --force --accept-package-agreements --accept-source-agreements
                Update-SessionPath
            }
            2 { # Android Studio
                Test-AdminPrivileges
                winget install --id Google.AndroidStudio -e --force --accept-package-agreements --accept-source-agreements
                Update-SessionPath
            }
            3 { # Notepad++
                Test-AdminPrivileges
                winget install --id Notepad++.Notepad++ -e --force --accept-package-agreements --accept-source-agreements
                Update-SessionPath
            }
            4 { # VS Code Editor
                Test-AdminPrivileges
                winget install --id Microsoft.VisualStudioCode -e --force --accept-package-agreements --accept-source-agreements
                Update-SessionPath
            }
            5 { # VS Code - Continue AI
                $codeBin = Get-CodeCliPath
                if ($codeBin) { & $codeBin --install-extension continue.continue --force }
            }
            6 { # Android SDK
                Test-AdminPrivileges
                winget install --id Google.AndroidSDK.PlatformTools -e --force --accept-package-agreements --accept-source-agreements
                Update-SessionPath
            }
            7 { # JAVA_HOME
                Test-AdminPrivileges
                $javaPaths = Get-ChildItem "C:\Program Files\Eclipse Adoptium", "C:\Program Files\Java" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '17' }
                if ($javaPaths) {
                    [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javaPaths[0].FullName, "User")
                    $env:JAVA_HOME = $javaPaths[0].FullName
                }
                Update-SessionPath
            }
            8 { # ANDROID_HOME
                Test-AdminPrivileges
                if (Test-Path $sdkDefault) {
                    [System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkDefault, "User")
                    $env:ANDROID_HOME = $sdkDefault
                    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
                    $platformTools = Join-Path $sdkDefault "platform-tools"
                    if ((Test-Path $platformTools) -and ($userPath -notlike "*platform-tools*")) {
                        [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$platformTools", "User")
                    }
                }
                Update-SessionPath
            }
            default {
                # Sem propadnou pouze dynamicky vložené tlačítka před koncem
                if ($selectedText -eq $(Get-Text 'RunAutoInstall' $L)) {
                    Test-AdminPrivileges
                    if (-not $nodeVer) { winget install --id OpenJS.NodeJS.LTS -e --force --accept-package-agreements --accept-source-agreements }
                    if (-not $javaVer) { winget install --id EclipseAdoptium.Temurin.17.JDK -e --force --accept-package-agreements --accept-source-agreements }
                    if (-not $nppExe) { winget install --id Notepad++.Notepad++ -e --force --accept-package-agreements --accept-source-agreements }
                    if (-not $codeExe) { winget install --id Microsoft.VisualStudioCode -e --force --accept-package-agreements --accept-source-agreements }
                    Update-SessionPath
                    if (-not $hasContinueMod) {
                        $codeBin = Get-CodeCliPath
                        if ($codeBin) { & $codeBin --install-extension continue.continue --force }
                    }
                    if (-not $asExe) { winget install --id Google.AndroidStudio -e --force --accept-package-agreements --accept-source-agreements }
                }
                elseif ($selectedText -eq $(Get-Text 'RunAutoEnv' $L)) {
                    Test-AdminPrivileges
                    if (Test-Path $sdkDefault) {
                        [System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkDefault, "User")
                        $env:ANDROID_HOME = $sdkDefault
                    }
                    $javaPaths = Get-ChildItem "C:\Program Files\Eclipse Adoptium", "C:\Program Files\Java" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '17' }
                    if ($javaPaths) {
                        [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javaPaths[0].FullName, "User")
                        $env:JAVA_HOME = $javaPaths[0].FullName
                    }
                    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
                    $platformTools = Join-Path $sdkDefault "platform-tools"
                    if ((Test-Path $platformTools) -and ($userPath -notlike "*platform-tools*")) {
                        [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$platformTools", "User")
                    }
                    Update-SessionPath
                }
            }
        }
    }
}

function Restore-ProjectFromBackup {
    param (
        [string]$RootPath,
        [string]$Lang
    )
    Clear-Host
    
    $backupDir = Join-Path $RootPath ".backup"

    if (-not (Test-Path $backupDir)) {
        Write-Host "`n$(Get-Text 'RestNoBackup' $Lang)" -ForegroundColor Yellow
        Write-Host "$(Get-Text 'PressKey' $Lang)" -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    $zipFiles = @(Get-ChildItem -Path $backupDir -Filter "*.zip" -File | Sort-Object -Property Name, LastWriteTime -Descending)

    if ($zipFiles.Count -eq 0) {
        Write-Host "`n$(Get-Text 'RestNoBackup' $Lang)" -ForegroundColor Yellow
        Write-Host "$(Get-Text 'PressKey' $Lang)" -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    $options = @()
    foreach ($zip in $zipFiles) {
        $options += "$($zip.Name) ($($zip.LastWriteTime.ToString('dd.MM.yyyy HH:mm')))"
    }
    $options += "$(Get-Text 'Back' $Lang)"

    $zipIndex = Show-Menu -Title "$(Get-Text 'RestMenu' $Lang)" -Options $options
    if ($zipIndex -eq -1 -or $zipIndex -eq ($options.Count - 1)) {
        return
    }

    $selectedZip = $zipFiles[$zipIndex]
    $tempExtractDir = Join-Path $env:TEMP "NodeRestore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($selectedZip.FullName, $tempExtractDir)

        $manifestPath = Join-Path $tempExtractDir "manifest.json"
        $projectName = ""
        $projectType = "nodejs" # Výchozí typ, pokud v manifestu chybí
        $modules = @()

        if (Test-Path $manifestPath) {
            try {
                $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($manifest.project_name) { $projectName = $manifest.project_name }
                if ($manifest.project_type) { $projectType = $manifest.project_type }
                if ($manifest.modules) { $modules = $manifest.modules }
            } catch {}
        }

        if ([string]::IsNullOrWhiteSpace($projectName)) {
            $projectName = $selectedZip.BaseName -replace '^Backup_', '' -replace '^\[[^\]]+\]_', '' -replace '_\d{4}-\d{2}-\d{2}.*$', ''
        }
        
        $projectName = Split-Path $projectName -Leaf
        $projectName = $projectName -replace '^[a-zA-Z]:', '' -replace '^[\\/]+', ''

        if ([string]::IsNullOrWhiteSpace($projectName) -or $projectName.Length -le 1) {
            $projectName = Read-Host "Project Name"
        }

        $targetProjectPath = Join-Path $RootPath $projectName
        if (Test-Path $targetProjectPath) {
            Write-Host "`n$(Get-Text 'RestExistWarning' $Lang) '$projectName'" -ForegroundColor Yellow
            $confirm = Read-Host "$(Get-Text 'RestOverwrite' $Lang)"
            if ($confirm -ne "Y" -and $confirm -ne "y" -and $confirm -ne "A" -and $confirm -ne "a" -and $confirm -ne "J" -and $confirm -ne "j") {
                return
            }
        } else {
            New-Item -ItemType Directory -Path $targetProjectPath -Force | Out-Null
        }

        # Kompletní překopírování obsahu archivu (mimo servisní manifest.json)
        Get-ChildItem -Path $tempExtractDir | Where-Object { $_.Name -ne "manifest.json" } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $targetProjectPath -Recurse -Force
        }

        Set-Location $targetProjectPath
        Write-Host "`nInstaluji závislosti (npm install)..." -ForegroundColor Cyan
        npm install

        # Specifické post-install kroky pouze pro Expo
        if ($projectType -eq "expo") {
            if ($modules.Count -gt 0) {
                $customModules = $modules | Where-Object { $_ -ne "react" -and $_ -ne "react-native" -and $_ -ne "expo" }
                if ($customModules.Count -gt 0) {
                    foreach ($mod in $customModules) { npx --yes expo install $mod --fix }
                }
            }
            npx --yes expo prebuild --clean
        }

        Write-Host "`n$(Get-Text 'RestSuccess' $Lang)" -ForegroundColor Green

    } catch {
        Write-Host "`n[ERROR] $_" -ForegroundColor Red
    } finally {
        if (Test-Path $tempExtractDir) {
            Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "`n$(Get-Text 'PressKey' $Lang)" -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Update-AndroidVersionCode {
    param ([string]$AppJsonPath)
    
    if (-not (Test-Path $AppJsonPath)) { return 1 }
    
    try {
        $rawJson = Get-Content $AppJsonPath -Raw -Encoding UTF8
        $jsonObj = $rawJson | ConvertFrom-Json
        
        # Zajištění struktury expo.android
        if ($null -eq $jsonObj.expo) { return 1 }
        if ($null -eq $jsonObj.expo.android) {
            $jsonObj.expo | Add-Member -MemberType NoteProperty -Name "android" -Value ([PSCustomObject]@{})
        }
        
        # Inkrementace versionCode
        $currentCode = 0
        if ($null -ne $jsonObj.expo.android.versionCode) {
            $currentCode = [int]$jsonObj.expo.android.versionCode
        }
        $newCode = $currentCode + 1
        
        # Zápis zpět do JSON objektu
        if ($null -eq $jsonObj.expo.android.PSobject.Properties["versionCode"]) {
            $jsonObj.expo.android | Add-Member -MemberType NoteProperty -Name "versionCode" -Value $newCode
        } else {
            $jsonObj.expo.android.versionCode = $newCode
        }
        
        $updatedJson = $jsonObj | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($AppJsonPath, $updatedJson, (New-Object System.Text.UTF8Encoding $false))
        
        Write-Host "[SYSTEM] Android versionCode incremented: $currentCode -> $newCode" -ForegroundColor Green
        return $newCode
    } catch {
        Write-Host "[WARNING] Could not increment versionCode: $_" -ForegroundColor Yellow
        return 1
    }
}

function Invoke-ProjectBackup {
    param (
        [string]$SelectedProject,
        [string]$ProjectPath,
        [string]$ProjectsRoot,
        [string]$PType,
        [string]$Lang
    )
    
    Write-Host "$(Get-Text 'BackupTitle' $Lang)" -ForegroundColor Cyan
    
    $backupDir = Join-Path $ProjectsRoot ".backup"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    # Zjištění verze z package.json nebo app.json
    $projVer = "1.0.0"
    $packageJsonPath = Join-Path $ProjectPath "package.json"
    $appJsonPath     = Join-Path $ProjectPath "app.json"

    # Nejprve zkusíme načíst verzi z app.json (Expo má prioritu)
    if (Test-Path $appJsonPath) {
        try {
            $appContent = Get-Content $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $appContent.expo -and [string]::IsNullOrWhiteSpace($appContent.expo.version) -eq $false) {
                $projVer = $appContent.expo.version.Trim()
            } elseif ([string]::IsNullOrWhiteSpace($appContent.version) -eq $false) {
                $projVer = $appContent.version.Trim()
            }
        } catch {}
    }

    # Pokud se verze z app.json nenačetla (nebo soubor neexistuje), zkusíme package.json
    if ($projVer -eq "1.0.0" -and (Test-Path $packageJsonPath)) {
        try {
            $pkgContent = Get-Content $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($pkgContent.version) -eq $false) {
                $projVer = $pkgContent.version.Trim()
            }
        } catch {}
    }

    $dateStr = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $tagType = $PType.ToUpper()
    $zipName = "Backup_[${tagType}]_${SelectedProject}_v${projVer}_${dateStr}.zip"
    $zipPath = Join-Path $backupDir $zipName

    try {
        $tempBackupDir = Join-Path $env:TEMP "NodeBackup_$SelectedProject"
        if (Test-Path $tempBackupDir) { Remove-Item $tempBackupDir -Recurse -Force }
        New-Item -ItemType Directory -Path $tempBackupDir -Force | Out-Null

        # Seznam závislostí pro manifest
        $modules = @()
        if (Test-Path $packageJsonPath) {
            try {
                $pkgContent = Get-Content $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($pkgContent.dependencies) {
                    $modules += $pkgContent.dependencies.psobject.Properties.Name
                }
                if ($pkgContent.devDependencies) {
                    $modules += $pkgContent.devDependencies.psobject.Properties.Name
                }
            } catch {}
        }

        # Vytvoření a zápis manifest.json
        $cfg = Get-Config
        $manifestData = [PSCustomObject]@{
            created_at   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            project_name = $SelectedProject
            project_type = $PType
            version      = $projVer
            author       = $cfg.Nick
            modules      = $modules
        }
        $manifestJson = $manifestData | ConvertTo-Json -Depth 3
        $manifestPath = Join-Path $tempBackupDir "manifest.json"
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding $false))

        # Kopírování kořenových souborů
        $filesToInclude = @(
            "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
            "server.js", "server.ts", "index.js", "index.ts", "App.js", "App.tsx",
            "app.json", "tsconfig.json", "nest-cli.json", "vite.config.js", "vite.config.ts",
            ".env.example", ".gitignore", "project.ini"
        )
        foreach ($file in $filesToInclude) {
            $filePath = Join-Path $ProjectPath $file
            if (Test-Path $filePath) {
                Copy-Item -Path $filePath -Destination $tempBackupDir -Force
            }
        }

        # Kopírování složek kódů a assetů
            $foldersToInclude = @("src", "assets", "public", "routes", "controllers", "models", "views", "lib", "config")
            foreach ($folder in $foldersToInclude) {
                $srcFolderPath = Join-Path $ProjectPath $folder
                if (Test-Path $srcFolderPath) {
                    # Složení cílové cesty se provede rovnou v závorce (bez mezikroku do proměnné)
                    Copy-Item -Path $srcFolderPath -Destination (Join-Path $tempBackupDir $folder) -Recurse -Force
                }
            }

        # Komprese složky
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempBackupDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        Remove-Item $tempBackupDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "`n$(Get-Text 'BackupSuccess' $Lang) $zipPath" -ForegroundColor Green
    } catch {
        Write-Host "`n$(Get-Text 'BackupFail' $Lang)$_" -ForegroundColor Red
    }
}

# --- MENU NASTAVENÍ BUILDERU ---
function Show-ConfigMenu {
    while ($true) {
        $cfg = Get-Config
        $L = $cfg.Language
        
        $opts = @(
            ("{0,-32} : [{1}]" -f $(Get-Text 'OpenJson' $L), $cfg.OpenAppJson),
            ("{0,-32} : [{1}]" -f $(Get-Text 'OpenTsx' $L), $cfg.OpenAppTsx),
            ("{0,-32} : [{1}]" -f $(Get-Text 'OpenJs' $L), $cfg.OpenAppJs),
            ("{0,-32} : [{1}]" -f $(Get-Text 'OpenIndex' $L), $cfg.OpenIndexJs),
            ("{0,-32} : [{1}]" -f $(Get-Text 'SFTPupload' $L), $cfg.uploadSFTP),
            ("{0,-32} : {1}"   -f $(Get-Text 'TargetPath' $L), $cfg.TargetPath),
            ("{0,-32} : {1}"   -f $(Get-Text 'DevNick' $L), $cfg.Nick),
            ("{0,-32} : [{1}]" -f $(Get-Text 'LangSelect' $L), $cfg.Language),
            ("{0,-32} : {1}"   -f $(Get-Text 'KeystorePath' $L), $cfg.KeystorePath),
            "[E] EDIT BUILDER.PS1",
            "[F] SFTP DEPLOYMENT CONFIGURATION",
            "[I] SETUP WIZARD (SYSTEM STATUS)",
            "$(Get-Text 'Back' $L)"
        )
        $idx = Show-Menu -Title "$(Get-Text 'Settings' $L)" -Options $opts -InitialIndex $global:configMenuIndex
        if ($idx -eq -1) { return }
        
        $global:configMenuIndex = $idx
        $selectedOpt = $opts[$idx]

        if ($selectedOpt -eq "$(Get-Text 'Back' $L)") {
            return
        }

        $cleanKey = ($selectedOpt -split ':')[0].Trim()

        switch ($cleanKey){
            $(Get-Text 'OpenJson' $L)   { $cfg.OpenAppJson = -not $cfg.OpenAppJson; Save-Config $cfg }
            $(Get-Text 'OpenTsx' $L)    { $cfg.OpenAppTsx  = -not $cfg.OpenAppTsx; Save-Config $cfg }
            $(Get-Text 'OpenJs' $L)     { $cfg.OpenAppJs   = -not $cfg.OpenAppJs; Save-Config $cfg }
            $(Get-Text 'OpenIndex' $L)  { $cfg.OpenIndexJs = -not $cfg.OpenIndexJs; Save-Config $cfg }
            $(Get-Text 'SFTPupload' $L) { $cfg.uploadSFTP  = -not $cfg.uploadSFTP; Save-Config $cfg }
            $(Get-Text 'TargetPath' $L)
            {
                Clear-Host
                $newTarget = Read-Host "$(Get-Text 'TargetPath' $L)"
                if (-not [string]::IsNullOrWhiteSpace($newTarget)) {
                    $cfg.TargetPath = $newTarget.Trim()
                    Save-Config $cfg
                }
            }
            $(Get-Text 'DevNick' $L)
            {
                Clear-Host
                $newNick = Read-Host "$(Get-Text 'DevNick' $L)"
                if (-not [string]::IsNullOrWhiteSpace($newNick)) {
                    $cfg.Nick = $newNick.Trim()
                    Save-Config $cfg
                    
                    $newIconPath = Join-Path $scriptDir "$($cfg.Nick).png"
                    if (-not (Test-Path $newIconPath)) {
                        try {
                            Add-Type -AssemblyName System.Drawing
                            $bmp = New-Object System.Drawing.Bitmap(64, 64)
                            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                            $gfx.Clear([System.Drawing.Color]::White)
                            $gfx.Dispose()
                            $bmp.Save($newIconPath, [System.Drawing.Imaging.ImageFormat]::Png)
                            $bmp.Dispose()
                            Start-Sleep -Seconds 1
                        } catch {
                            [System.IO.File]::WriteAllText($newIconPath, "DUMMY PNG")
                        }
                    }
                }
            }
            $(Get-Text 'LangSelect' $L)
            {
                $langOpts = @("English (EN)", "Deutsch (DE)", "Čeština (CZ)")
                $currentIdx = switch ($cfg.Language) { "CZ" { 2 } "DE" { 1 } default { 0 } }
                
                $lIdx = Show-Menu -Title "LANGUAGE SELECTION" -Options $langOpts -InitialIndex $currentIdx
                if ($lIdx -ne -1) {
                    if ($lIdx -eq 0) { $cfg.Language = "EN" }
                    elseif ($lIdx -eq 2) { $cfg.Language = "CZ" }
                    else { $cfg.Language = "DE" }
                    Save-Config $cfg
                }
            }
            $(Get-Text 'KeystorePath' $L)
            {
                Clear-Host
                $newKeystore = Read-Host "$(Get-Text 'KeystorePath' $L)"
                if (-not [string]::IsNullOrWhiteSpace($newKeystore)) {
                    $cfg.KeystorePath = $newKeystore.Trim()
                    Save-Config $cfg
                }
            }
            "[E] EDIT BUILDER.PS1" { 
                Open-SelfInNotepad 
            }
            "[F] SFTP DEPLOYMENT CONFIGURATION" { 
                Show-SetupSFTP 
            }
            "[I] SETUP WIZARD (SYSTEM STATUS)" { 
                Show-SetupWizard 
            }
        }
    }
}

# --- HLAVNÍ SMYČKA PROGRAMU ---
while ($true) {
    Set-Location $projectsRoot

    $cfg = Get-Config
    $L = $cfg.Language

    $rawProjects = @(Get-ChildItem -Path $projectsRoot -Directory | 
                Where-Object { $_.Name -notmatch '^[_\.]' -and $_.Name -ne 'android' } | 
                Select-Object -ExpandProperty Name)

    $projects = @()
    $menuList = @()
    foreach ($p in $rawProjects) {
        $pPath = Join-Path $projectsRoot $p
        $pType = Get-ProjectType -ProjectPath $pPath
        $tag = switch ($pType) {
            "expo"   { "[EXPO]" }
            "nodejs" { "[NODEJS]" }
            default  { "[UNK]" }
        }
        $projects += $p
        $menuList += "$tag $p"
    }

    $menuList += "$(Get-Text 'CreateNew' $L)"
    $menuList += "$(Get-Text 'RestoreBackup' $L)"
    $menuList += "$(Get-Text 'Settings' $L)"
    $menuList += "$(Get-Text 'Exit' $L)"

    $pIndex = Show-Menu -Title "$(Get-Text 'SelectProject' $L) ($projectsRoot)" -Options $menuList -InitialIndex $global:mainMenuIndex
    if ($pIndex -ne -1) { $global:mainMenuIndex = $pIndex } else {
        Clear-Host
        return
    }

    $lastIndex = $menuList.Count - 1      
    $configIndex = $menuList.Count - 2    
    $restoreIndex = $menuList.Count - 3   
    $newProjIndex = $menuList.Count - 4   

    if ($pIndex -eq $lastIndex) {
        Clear-Host
        return
    }

    if ($pIndex -eq $configIndex) {
        Show-ConfigMenu
        continue
    }

    if ($pIndex -eq $restoreIndex) {
        Restore-ProjectFromBackup -RootPath $projectsRoot -Lang $L
        continue
    }
    # --- NOVÝ PROJEKT ---
    if ($pIndex -eq $newProjIndex) {
        # 1. KROK: VÝBĚR TYPU PROJEKTU (NEJPRVE)
        $typeOptions = @(
            "1) Expo (Android / iOS App)",
            "2) Node.js (Web / API)",
            "$(Get-Text 'Back' $L)"
        )
        
        $tIndex = Show-Menu -Title "SELECT PROJECT TYPE" -Options $typeOptions
        if ($tIndex -eq -1 -or $tIndex -eq 2) { 
            continue 
        }

        # 2. KROK: ZADÁNÍ NÁZVU PROJEKTU (AŽ PO VÝBĚRU TYPU)
        Clear-Host
        $rawInputName = Read-Host "$(Get-Text 'EnterProjName' $L)"

        if ([string]::IsNullOrWhiteSpace($rawInputName)) {
            continue
        }

        $userNick = if (-not [string]::IsNullOrWhiteSpace($cfg.Nick)) { $cfg.Nick.Trim() } else { "Dev" }
        $userNickLow = ($userNick.ToLower() -replace '[^a-z0-9]', '')

        $formattedName = $rawInputName.Trim()
        $normalized = $formattedName.Normalize([System.Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($char in $normalized.ToCharArray()) {
            if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($char)
            }
        }
        $cleanFolderName = $sb.ToString() -replace '\s+', '_' -replace '[^a-zA-Z0-9_\-]', '' -replace '_+', '_'
        $slugName = $cleanFolderName.ToLower()

        $newProjectPath = Join-Path $projectsRoot $cleanFolderName
        if (Test-Path $newProjectPath) {
            Write-Host "`n$(Get-Text 'ProjExists' $L) ($cleanFolderName)" -ForegroundColor Red
            Write-Host "$(Get-Text 'PressKey' $L)" -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            continue
        }

        Set-Location $projectsRoot
        Write-Host "`n$(Get-Text 'CreatingProj' $L) $cleanFolderName" -ForegroundColor Cyan

        if ($tIndex -eq 0) {
            # ==========================================
            # VĚTEV EXPO
            # ==========================================
            npx --yes create-expo-app@latest $cleanFolderName --template blank

            if ($?) {
                Set-Location $newProjectPath

                # Zápis konfiguračního souboru projektu
                [System.IO.File]::WriteAllText((Join-Path $newProjectPath "project.ini"), "ProjectType = expo`r`n", (New-Object System.Text.UTF8Encoding $false))

                # Vstupní bod index.js
                $indexJsContent = "import { registerRootComponent } from 'expo';`nimport App from './App';`n`nregisterRootComponent(App);"
                [System.IO.File]::WriteAllText((Join-Path $newProjectPath "index.js"), $indexJsContent, (New-Object System.Text.UTF8Encoding $false))

                # Příprava složky assets v projektu
                $assetsFolder = Join-Path $newProjectPath "assets"
                if (-not (Test-Path $assetsFolder)) { 
                    New-Item -ItemType Directory -Path $assetsFolder -Force | Out-Null 
                }

                # Kopírování ikony z .templates/expo/assets/
                $templateAssetsDir = Join-Path $expoTemplateDir "assets"
                $customIcon = Join-Path $templateAssetsDir "$userNick.png"
                if (-not (Test-Path $customIcon)) {
                    $customIcon = Get-ChildItem -Path $templateAssetsDir -Filter "*.png" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
                }

                if ($customIcon -and (Test-Path $customIcon)) {
                    $targetIconPath = Join-Path $assetsFolder "$userNick.png"
                    Copy-Item -Path $customIcon -Destination $targetIconPath -Force
                }

                # Aplikování šablony app.json z .templates/expo/app.json
                $targetAppJson = Join-Path $newProjectPath "app.json"
                if (Test-Path $templateJson) {
                    $rawContent = Get-Content -Path $templateJson -Raw -Encoding UTF8
                    $rawContent = $rawContent -replace 'usernick_low', $userNickLow
                    $rawContent = $rawContent -replace 'usernick', $userNick
                    $rawContent = $rawContent -replace '"name":\s*".*?"', "`"name`": `"$formattedName`""
                    $rawContent = $rawContent -replace '"slug":\s*".*?"', "`"slug`": `"$slugName`""
                    $rawContent = $rawContent -replace '"package":\s*".*?"', "`"package`": `"com.$userNickLow.$slugName`""
                    [System.IO.File]::WriteAllText($targetAppJson, $rawContent, (New-Object System.Text.UTF8Encoding $false))
                }

                npx --yes expo prebuild --clean
                Write-Host "`n$(Get-Text 'ProjSuccess' $L)" -ForegroundColor Green
            } else {
                Write-Host "`n$(Get-Text 'ProjFailed' $L)" -ForegroundColor Red
            }
        } elseif ($tIndex -eq 1) {
            # ==========================================
            # VĚTEV NODE.JS
            # ==========================================
            New-Item -ItemType Directory -Path $newProjectPath -Force | Out-Null
            Set-Location $newProjectPath
            
            [System.IO.File]::WriteAllText((Join-Path $newProjectPath "project.ini"), "ProjectType = nodejs`r`n", (New-Object System.Text.UTF8Encoding $false))

            if (Test-Path $nodejsTemplateDir) {
                $itemsToCopy = Get-ChildItem -Path $nodejsTemplateDir
                if ($itemsToCopy.Count -gt 0) {
                    Copy-Item -Path "$nodejsTemplateDir\*" -Destination $newProjectPath -Recurse -Force
                }
            }

            $targetPkgJson = Join-Path $newProjectPath "package.json"
            if (-not (Test-Path $targetPkgJson)) { $fallbackPkg = @{
                    name = $slugName
                    version = "1.0.0"
                    main = "index.js"
                    scripts = @{ dev = "node index.js" }
                } | ConvertTo-Json
                [System.IO.File]::WriteAllText($targetPkgJson, $fallbackPkg, (New-Object System.Text.UTF8Encoding $false))
            }

            Write-Host "`n$(Get-Text 'ProjSuccess' $L)" -ForegroundColor Green
        }

        Write-Host "`n$(Get-Text 'PressKey' $L)" -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        continue
    }

    $selectedProject = $projects[$pIndex]
    $projectPath = Join-Path $projectsRoot $selectedProject
    $pType = Get-ProjectType -ProjectPath $projectPath
    Set-Location $projectPath

    while ($true) {
        $actionList = @(
            if ($pType -eq "expo") {
            "$(Get-Text 'Act1' $L)"
            "$(Get-Text 'Act2' $L)"
            "$(Get-Text 'Act3' $L)"
            "$(Get-Text 'Act4' $L)"
            "$(Get-Text 'Act5' $L)"
            "$(Get-Text 'Act6' $L)"
            "$(Get-Text 'Act7' $L)"
            "$(Get-Text 'ActAabBuild' $L)"
            "$(Get-Text 'ActCleanCache' $L)"           
            }
            "$(Get-Text 'ActBackup' $L)"
            "$(Get-Text 'ActDel' $L)"
            "$(Get-Text 'ActBack' $L)"
        )

        $aIndex = Show-Menu -Title "PROJECT: $selectedProject" -Options $actionList -InitialIndex $global:projectMenuIndex

        # Pokud uživatel zmáčkl Esc ($aIndex -eq -1)
        if ($aIndex -eq -1) { break }

        $global:projectMenuIndex = $aIndex
        $selectedAction = $actionList[$aIndex]

        if ($selectedAction -eq "$(Get-Text 'ActBack' $L)") {
            break
        }

        Clear-Host
        Write-Host "$(Get-Text 'WorkingOn' $L) $selectedProject`n" -ForegroundColor Green
        $skipPause = $false
        $exitToMainMenu = $false

        switch ($selectedAction) {
            "$(Get-Text 'Act1' $L)"{
                Open-InNotepadPlusPlus -ProjectPath $projectPath -Lang $L
            }
            "$(Get-Text 'Act2' $L)"{
                $commonModules = @(
                    @{ Name = "react-native-webview" },
                    @{ Name = "@react-native-async-storage/async-storage" },
                    @{ Name = "@react-native-community/netinfo" },
                    @{ Name = "expo-location" },
                    @{ Name = "expo-notifications" },
                    @{ Name = "expo-quick-actions" },
                    @{ Name = "@react-navigation/native @react-navigation/native-stack" },
                    @{ Name = "react-native-safe-area-context" },
                    @{ Name = "@expo/vector-icons" }
                )

                $modOptions = @("$(Get-Text 'InstallBasic' $L)")
                foreach ($m in $commonModules) {$modOptions += "$($m.Name)" }
                $modOptions += "$(Get-Text 'InstallCustom' $L)"
                $modOptions += "$(Get-Text 'Back' $L)"

                $modIndex = Show-Menu -Title "PACKAGES ($selectedProject)" -Options $modOptions
                if ($modIndex -eq -1 -or $modIndex -eq ($modOptions.Count - 1)) {
                    $skipPause = $true
                    continue
                }

                Clear-Host
                if ($modIndex -eq 0) { $allPkgs = ($commonModules | ForEach-Object { $_.Name }) -join " "
                    npx --yes expo install $allPkgs
                } elseif ($modIndex -eq ($modOptions.Count - 2)) { $customPkg = Read-Host "$(Get-Text 'EnterPkg' $L)"
                    if (-not [string]::IsNullOrWhiteSpace($customPkg)) {
                        npx --yes expo install $customPkg.Trim()
                    }
                } else {
                    npx --yes expo install $commonModules[$modIndex - 1].Name
                }
                $skipPause = $true
            }
            "$(Get-Text 'Act3' $L)"{
                Write-Host "$(Get-Text 'StartExpo' $L)" -ForegroundColor Cyan
                Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$projectPath'; npx expo start -c"
            }
            "$(Get-Text 'Act4' $L)" {
                Write-Host "$(Get-Text 'FastBuild' $L)" -ForegroundColor Cyan
                Push-Location android
                .\gradlew assembleRelease
                $buildSuccess = ($LASTEXITCODE -eq 0)
                Pop-Location

                if ($buildSuccess) {
                    $savedApk = Publish-Apk -ProjectName $selectedProject -ProjectPath $projectPath -Lang $L
                    
                    if ($savedApk -and $cfg.uploadSFTP) {
                        Publish-ApkToSftp -ProjectPath $projectPath -ProjectName $selectedProject -ApkFilePath $savedApk
                    }
                } else {
                    Write-Host "`n$(Get-Text 'BuildFail' $L) $LASTEXITCODE" -ForegroundColor Red
                }
            }
            "$(Get-Text 'Act5' $L)" {
                Write-Host "$(Get-Text 'KillJava' $L)" -ForegroundColor Cyan
                cmd /c "taskkill /f /im java.exe 2>nul"

                Write-Host "`n$(Get-Text 'CleanRegen' $L)" -ForegroundColor Cyan
                npx --yes expo prebuild --clean

                if ($?) {
                    Push-Location android
                    .\gradlew clean
                    .\gradlew assembleRelease
                    $buildSuccess = ($LASTEXITCODE -eq 0)
                    Pop-Location
                } else { $buildSuccess = $false }

                if ($buildSuccess) {
                    $savedApk = Publish-Apk -ProjectName $selectedProject -ProjectPath $projectPath -Lang $L
                    
                    if ($savedApk -and $cfg.uploadSFTP) {
                        Publish-ApkToSftp -ProjectPath $projectPath -ProjectName $selectedProject -ApkFilePath $savedApk
                    }
                } else {
                    Write-Host "`n$(Get-Text 'BuildFail' $L)" -ForegroundColor Red
                }
            }
            "$(Get-Text 'Act6' $L)"{ npx --yes expo install --fix }
            "$(Get-Text 'Act7' $L)"{
                npx --yes expo install --fix
                npx --yes expo-doctor
            }
            
            "$(Get-Text 'ActAabBuild' $L)" {
                Write-Host "=== PRODUCTION AAB BUILD (GOOGLE PLAY) ===" -ForegroundColor Cyan
                
                $appJsonPath = Join-Path $projectPath "app.json"
                $newVerCode = Update-AndroidVersionCode -AppJsonPath $appJsonPath
                
                Push-Location android
                .\gradlew bundleRelease
                $buildSuccess = ($LASTEXITCODE -eq 0)
                Pop-Location

                if ($buildSuccess) {
                    # Přesun .aab souboru do výstupní složky
                    $aabSource = Join-Path $projectPath "android\app\build\outputs\bundle\release\app-release.aab"
                    $cfg = Get-Config
                    $targetDir = $cfg.TargetPath
                    
                    if (Test-Path $aabSource) {
                        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                        
                        # Načtení slugu a verze
                        $appConfig = Get-Content $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $slug = $selectedProject
                        $ver = "1.0.0"
                        if ($appConfig.expo.slug) { $slug = $appConfig.expo.slug }
                        if ($appConfig.expo.version) { $ver = $appConfig.expo.version }
                        
                        $aabDestination = Join-Path $targetDir "$($slug)_v${ver}_b${newVerCode}.aab"
                        Move-Item -Path $aabSource -Destination $aabDestination -Force
                        Write-Host "`n[SUCCESS] AAB successfully saved to: $aabDestination" -ForegroundColor Green

                        Write-Host "`nCreating automatic backup of the updated production state..." -ForegroundColor Cyan
                        Invoke-ProjectBackup -SelectedProject $selectedProject -ProjectPath $projectPath -ProjectsRoot $projectsRoot -PType $pType -Lang $L
                    }
                } else {
                    Write-Host "`n[ERROR] Production AAB build failed!" -ForegroundColor Red
                }
            }

            "$(Get-Text 'ActCleanCache' $L)" {
                Write-Host "$(Get-Text 'CleanCacheTitle' $L)" -ForegroundColor Cyan

                # 1. Ukončení běžících Node.js a Java procesů (uvolnění zámků na soubory)
                Write-Host "`n[1/6] Stopping running Node and Java processes..." -ForegroundColor Yellow
                cmd /c "taskkill /f /im node.exe 2>nul"
                cmd /c "taskkill /f /im java.exe 2>nul"
                Start-Sleep -Seconds 1

                # 2. Vyčištění Gradle buildu ve složce android/
                if (Test-Path (Join-Path $projectPath "android")) {
                    Write-Host "[2/6] Cleaning Gradle build files (android/.gradle & android/app/build)..." -ForegroundColor Yellow
                    Push-Location android
                    try {
                        .\gradlew clean
                    } catch {}
                    Pop-Location

                    $androidGradleCache = Join-Path $projectPath "android\.gradle"
                    if (Test-Path $androidGradleCache) {
                        Remove-Item -Path $androidGradleCache -Recurse -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Host "[2/6] Android folder not prebuilt yet, skipping Gradle clean." -ForegroundColor Gray
                }

                # 3. Vyčištění Metro Bundler & Expo Cache v uživatelském profilu
                Write-Host "[3/6] Clearing Metro Bundler & Expo caches..." -ForegroundColor Yellow
                $envTemp = $env:TEMP
                $localAppData = $env:LOCALAPPDATA

                $cachesToDelete = @(
                    (Join-Path $envTemp "metro-*"),
                    (Join-Path $envTemp "haste-map-*"),
                    (Join-Path $envTemp "react-*"),
                    (Join-Path $envTemp "expo-cli-*"),
                    (Join-Path $localAppData "Expo"),
                    (Join-Path $projectPath ".expo")
                )

                foreach ($cachePath in $cachesToDelete) {
                    if (Test-Path $cachePath) {
                        Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                # 4. Vyčištění dočasných složek balíčkovacího systému (npm / yarn / watchman)
                Write-Host "[4/6] Cleaning NPM / Watchman cache..." -ForegroundColor Yellow
                try {
                    npx --yes watchman watch-del-all 2>$null
                } catch {}

                # 5. Volitelné čištění lock souborů nebo node_modules/.cache
                $nodeModulesCache = Join-Path $projectPath "node_modules\.cache"
                if (Test-Path $nodeModulesCache) {
                    Write-Host "[5/6] Cleaning node_modules/.cache..." -ForegroundColor Yellow
                    Remove-Item -Path $nodeModulesCache -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Host "[5/6] node_modules/.cache is already clean." -ForegroundColor Gray
                }

                # 6. Resetování Expo štítku / re-index
                Write-Host "[6/6] Verifying project integrity..." -ForegroundColor Yellow
                
                Write-Host "`n$(Get-Text 'CleanCacheSuccess' $L)" -ForegroundColor Green
            }

            "$(Get-Text 'ActBackup' $L)" {
                Invoke-ProjectBackup -SelectedProject $selectedProject -ProjectPath $projectPath -ProjectsRoot $projectsRoot -PType $pType -Lang $L
            }

            "$(Get-Text 'ActDel' $L)" {
                Write-Host "$(Get-Text 'DelTitle' $L)" -ForegroundColor Cyan
                
                $backupDir = Join-Path $projectsRoot ".backup"
                $existingBackups = @()
                if (Test-Path $backupDir) {
                    $existingBackups = @(Get-ChildItem -Path $backupDir -Filter "*.zip" -File | Where-Object { 
                        $_.Name -match "^Backup_(\[[^\]]+\]_)?$([regex]::Escape($selectedProject))_v"
                    })
                }

                if ($existingBackups.Count -eq 0) {
                    Write-Host "`n$(Get-Text 'DelNoBackup' $L)" -ForegroundColor Red
                } else {
                    Write-Host "`n$(Get-Text 'DelFound' $L)" -ForegroundColor Green
                }

                $confirm = Read-Host "`n$(Get-Text 'DelConfirm' $L) '$selectedProject'? (Y/N)"
                if ($confirm -match '^[YyAaJj]') {
                    cmd /c "taskkill /f /im node.exe 2>nul"
                    cmd /c "taskkill /f /im java.exe 2>nul"
                    Start-Sleep -Seconds 1

                    $emptyDir = Join-Path $env:TEMP "empty_dir_for_delete"
                    if (-not (Test-Path $emptyDir)) { 
                        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null 
                    }
                    Set-Location $projectsRoot

                    robocopy $emptyDir $projectPath /MIR /NFL /NDL /NJH /NJS /NC /NS | Out-Null
                    Remove-Item -Path $projectPath -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $emptyDir -Recurse -Force -ErrorAction SilentlyContinue

                    Write-Host "`n$(Get-Text 'DelSuccess' $L)" -ForegroundColor Green
                    Write-Host "$(Get-Text 'PressKey' $L)" -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    
                    $skipPause = $true
                    $exitToMainMenu = $true
                }
            }
        }

        # Pokud projekt byl smazán, vyskočíme ze smyčky projektu do hlavního menu
        if ($exitToMainMenu) {
            break
        }

        if (-not $skipPause) {
            Write-Host "`n$(Get-Text 'PressKey' $L)" -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}