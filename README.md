# ⚡ Ghost-OS Command Center

Ghost-OS is a lightweight, zero-footprint **Mobile Edge-Client** built with Flutter. It serves as a rugged remote terminal and telemetry dashboard specifically designed to control and monitor a headless **Edge AI Hub** (e.g., Raspberry Pi or local Python/Node server) over a local network.

Featuring a striking **Brutalist / Boxy Code-Editor Aesthetic**, Ghost-OS turns any Android or iOS device into a mobile hacker terminal that persists absolutely zero state locally—all history, storage, and logic live purely on the remote hub.

---

## ✨ Core Features

*   **Zero-Footprint Architecture:** The mobile app acts purely as a thin client window. No logs, history, or configurations permanently reside on the phone. All payload execution happens natively on the remote edge hub.
*   **Encrypted WebSockets Uplink:** Real-time bi-directional streaming for command input, sub-millisecond sensor telemetry, and terminal logging. 
*   **Brutalist Visual Paradigm:** Sharp edges, pure white code blocks, and aggressive `#FF4D00` (Neon Orange) offset dropshadows optimized for legibility and developer aesthetic.
*   **Dynamic Telemetry Dashboards:** Live system interception of system hardware states (CPU, RAM, DISK) mapped instantly to UI widget meters.
*   **Advanced Voice Synthesis:**
    *   **Primary:** High-fidelity Voice inference using the ElevenLabs API for human-like auditory feedback.
    *   **Fallback Sequence:** In the event of an API quota limit `429`, pure network blackout (DNS lookup failure), or router block, the app seamlessly cascades to a native `flutter_tts` offline engine with zero interruption.
*   **Voice-To-Command:** Native physical STT (Speech-to-Text) allowing you to dictate raw terminal bash commands directly from your phone's microphone.

---

## 🛠️ Architecture

The ecosystem functions dynamically across two components:

1.  **The Engine (Backend):** A headless FastAPI / Node WebSocket Server deployed on an Edge Device (Raspberry Pi/Laptop) acting as the main brain.
2.  **The Interface (Frontend):** This repository. The Ghost-OS Flutter Application.

---

## 🚀 Quick Start (Running Locally)

### 1. Prerequisites
*   Flutter SDK (Version `3.24.0` or higher)
*   Android SDK version 36 (Kotlin `2.1.0`)

### 2. Physical Initialization
Clone this repository and verify your Flutter dependencies are healthy:
```bash
git clone https://github.com/anirban222777das/GhostOS-App.git
cd GhostOS-App
flutter clean
flutter pub get
```

### 3. Edge Hub Connectivity Target
Locate the `lib/main.dart` source file and update the `kDefaultHubIp` string on line 18 to align with the local static IPv4 address of your Raspberry Pi / Hub Server on your Wi-Fi network:
```dart
const String kDefaultHubIp = '192.168.1.XX';
const int kHubPort = 8000;
```

### 4. Deploy to Device
Attach an Android/iOS emulator or a physical device:
```bash
flutter run
```

---

## 🔑 ElevenLabs Voice Key Configuration

Ghost-OS ships with ElevenLabs `text-to-speech` logic. Rather than hard-coding it in the script, the interface provides a physical entry mechanism.

1.  Tap the **Settings Icon** on the right side of the Ghost-OS Terminal App-Bar.
2.  Input your `xi-api-key`.
3.  Hit **SAVE KEY**. *(Note: the key is validated over HTTP, but forcefully stored via SharedPreferences even if your mobile device is currently offline due to strict AirGapping).*

---

## 🎨 Theme UI Tokens

If you wish to modify the application's Brutalist Theme, alter the core Palette constants in `lib/main.dart`:

```dart
const Color kScaffoldBlack = Color(0xFF111111); // Deep Slate Background
const Color kThemeOrange = Color(0xFFFF4D00);   // Neon Accent 
const Color kBoxyShadowColor = Color(0xFFFF4D00); // Sharp Dropshadows
const Color kBoxyBorderColor = Color(0x66FFFFFF); // Block Outlines
```

---

*Ghost-OS: Built for the Edge.* 📡
