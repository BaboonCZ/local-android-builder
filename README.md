# 🚀 Local Android & Node.js Builder CLI

A robust, interactive PowerShell-based CLI tool designed to manage the entire lifecycle of local Android (Expo / React Native) and Node.js projects. This utility automates environment setup, project creation, dependency management, compilation, cache wiping, and **direct SFTP deployment** with auto-generated version manifests—all without relying on cloud-based build services.

---

## ✨ Key Features

### 📦 Full Build Lifecycle
Manage everything locally: scaffold a new Expo app, run a local dev server, compile standalone APKs, or generate Google Play-ready AAB production bundles with automated `versionCode` incrementation.

### 🛠️ Automated Environment Setup
A built-in Setup Wizard checks and automatically installs missing dependencies via Windows Package Manager (`winget`). It natively handles:
* Node.js (LTS), OpenJDK 17, Android Studio, VS Code, and Notepad++.
* Automatic injection and configuration of `JAVA_HOME`, `ANDROID_HOME`, and SDK platform tools into Windows environment variables.

### 🚀 1-Click SFTP Deployment & Auto-Updates
Securely deploy compiled `.apk` files directly to your company's SFTP server using native Windows `curl.exe`. 
* Generates a lightweight `version.json` file during deployment (containing `packageName`, `version`, `versionCode`, `apkUrl`, and `updatedAt`) to facilitate seamless in-app auto-updating for your users.

### 🗄️ Intelligent Backup & Restore
Creates timestamped `.zip` archives of source code and assets.
* **Smart Exclusion:** Automatically ignores heavy `node_modules` and build directories to keep backups fast and lightweight.
* **Manifest Injection:** Injects a `manifest.json` containing project metadata and NPM dependencies, allowing automatic dependency re-installation upon restoration.

### 🧹 Deep Cache & Maintenance Management
Resolves common React Native / Expo build issues instantly.
* Safely terminates locked Java/Node processes.
* Aggressively clears Metro Bundler, Gradle, NPM, and Watchman caches.
* **MAX_PATH Bypass:** Utilizes a `robocopy /MIR` mirroring trick to instantly delete deeply nested `node_modules` folders, bypassing the classic Windows 260-character path limit.

### 🌍 Multi-Language UI
Fully interactive, keyboard-driven CLI menu natively localized in **English**, **German**, and **Czech**.

---

## 🔒 Security & Architecture Highlights

* **Zero Plain-Text Passwords:** SFTP passwords are encrypted using the **Windows DPAPI** (`ConvertFrom-SecureString`) and tied to your specific Windows user profile. Your `builder.ini` configuration file never contains plain-text credentials.
* **Native Transfer:** Uses Windows native `curl.exe --insecure` to handle SFTP transfers, bypassing the need for third-party FTP clients (ideal for internal corporate servers without public CAs).

---

## 📋 Prerequisites

* **OS:** Windows 10 or Windows 11
* **Shell:** PowerShell 5.1 or later
* **Permissions:** Administrator rights are only required for the initial setup.

---

## 🚀 Installation & Usage

1. **Download/Clone:** Clone or download this repository into your designated workspace folder.
2. **First Run (Initial Setup):** Right-click on `builder.ps1` and select **Run with PowerShell** as **Administrator**. Elevated privileges are required just once to register system paths and install missing tools via Winget.
3. **Subsequent Runs:** Launch `builder.ps1` normally or use the generated `builder.cmd` command prompt alias without administrator rights. The tool will automatically request elevation only if system-level actions are triggered.
4. **Configuration:** On the first execution, the wizard will prompt you for your preferred UI Language and Developer Nickname.

---

## 🗂️ Project Structure

"""text
├── builder.ps1          # Core PowerShell execution script
├── builder.cmd          # Command prompt launcher alias (auto-generated)
├── builder.ini          # Configuration file (stores settings & DPAPI encrypted SFTP hash)
├── .templates/          # Scaffolding templates (app.json, fallback assets)
│   ├── expo/
│   └── nodejs/
└── .backup/             # Destination directory for all project ZIP archives
"""

---

## ⚙️ Generated Manifest Schema (version.json)

When SFTP Upload is enabled, compiling a build generates and uploads the following payload alongside your APK. This allows your mobile application to fetch the JSON and prompt users to download updates automatically:

json
{
  "packageName": "com.developer.appname",
  "version": "1.0.5",
  "versionCode": 12,
  "apkUrl": "https://www.mydomain.com/app_folder/appname_v1.0.5.apk",
  "updatedAt": "2026-09-19 20:45:00"
}


---

## 🎮 Menu Structure Overview

### 🏠 Main Menu
* **Select Project:** Choose an existing project to open its dedicated action menu.
* **Create New Project:** Interactive wizard for Expo (Android/iOS) or Node.js project scaffolding.
* **Restore Project:** Extract and reinstall dependencies from a `.backup` ZIP archive.
* **Builder Settings:** Manage UI preferences, DPAPI-encrypted SFTP credentials, target build paths, and run the System Setup Wizard.

### 📱 Project Action Menu (Expo Example)
* **Open configured files:** Fast editing access to `app.json`, `App.tsx`, `index.js` in Notepad++.
* **Install Expo/NPM packages:** Quick selector for essential native packages (Navigation, Safe Area, Async Storage) or custom NPM modules.
* **Start Expo Go dev server:** Launches `npx expo start -c` in an isolated process.
* **Fast incremental build:** Compiles incremental changes into a release APK (`assembleRelease`).
* **Clean regen & build:** Executes `expo prebuild --clean` followed by a fresh Gradle build.
* **Build App Bundle (.aab):** Increments `versionCode`, builds a production AAB for Google Play, and triggers an automated source backup.

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 📸 Preview

<img width="476" height="475" alt="builder_en" src="https://github.com/user-attachments/assets/675a6d95-b901-4172-91b7-f70111800d0f" />
