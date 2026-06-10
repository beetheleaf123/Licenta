# Proiect Licență: Smart Home Hub

## Obiective și Context
Acest proiect vizează realizarea unui sistem de Smart Home integrat, utilizând un Raspberry Pi ca server central și Flutter pentru interfața utilizator, incluzând un asistent AI local integrat cu Gemini API și funcții de control.

## Harta Locațiilor File System (Windows / RPi)
Pentru editarea directă a fișierelor de pe Raspberry Pi din mediul Windows, se utilizează unitatea de rețea `Z:` (care este mapată la rădăcina `/` a sistemului RPi).
* **Workspace Flutter (Local Windows):** `e:\smart_app\flutter_application_1`
* **Network Drive RPi (Windows mapping):** `Z:\` (corespunde cu `/` pe Raspberry Pi)

## Arhitectură Tehnică (Full Map)

### 1. Server Central (Raspberry Pi)
- **IP:** `192.168.1.137`
- **Broker MQTT:** Mosquitto (Port 1883).
- **Backend REST API:** Flask (Port 5000) pentru date istorice.

### 2. Servicii Background (systemd)
Sistemul rulează servicii critice care pornesc automat la boot (în `/home/mrz/HubMQTT` sub virtual env):
- **`smarthome_devices.service`**:
    - **Script RPi:** `/home/mrz/HubMQTT/device_manager.py`
    - **Windows Path:** `Z:\home\mrz\HubMQTT\device_manager.py`
    - **Rol:** Bridge MQTT. Gestionează criptarea AES pentru Sonoff, controlul `pywizlight` și automatizările locale (ex: aprindere lumini la lux scăzut, sincronizare setări locație din SQLite).
- **`smarthome_api.service`**:
    - **Script RPi:** `/home/mrz/Sonoff/api.py`
    - **Windows Path:** `Z:\home\mrz\Sonoff\api.py`
    - **Rol:** Expune endpoint-urile `/istoric` și `/istoric_complet` pentru interfața Flutter.
- **Asistent AI (Luffy Chat Engine)**:
    - **Scripturi RPi:** 
        - `/home/mrz/HubMQTT/ai_engine.py` (Windows Path: `Z:\home\mrz\HubMQTT\ai_engine.py`): Folosește `google-genai` SDK (v2.7.0) cu modelul `gemini-2.5-flash` și manual loop pentru Function Calling.
        - `/home/mrz/HubMQTT/chat_api.py` (Windows Path: `Z:\home\mrz\HubMQTT\chat_api.py`): Handler MQTT care ascultă pe `smarthome/chat/user_message` și publică pe `smarthome/chat/bot_response`. Salvează conversațiile în SQLite `chat_history`.

### 3. Dispozitive Integrate
- **Senzor Climat:** Sonoff THR cu BME280 (Topic: `tele/sonoff/SENSOR`).
- **Lumină:** Bec Philips WiZ (`192.168.1.130`). Controlat prin `smarthome/bulb/command`.
- **Energie:** Priză Inteligentă S60 (`192.168.1.138`). Necesită AES Payload (ID: `10027f4f64`, Key: `f656...`).

### 4. Tehnologii Frontend (Flutter)
- **Entry Point:** `lib/main_v2CLAUDE.dart` (Dashboard & Weather Card cu Open-Meteo API).
- **Asistent AI Chat UI:** `lib/chat_screen.dart` (Chat UI cu inline charts, typing indicator) și `lib/chat_service.dart` (MQTT client provider).
- **Dependențe Cheie:** `fl_chart` (grafice în timp real și inline charts), `mqtt_client` (comunicare real-time), `http` (fetch istoric și geocoding/forecast Open-Meteo).
- **Servicii:** `MqttServiceV2`, `ApiServiceV2`, `ChatService`.

## Instrucțiuni de Colaborare (Persona)
- **Rol:** Mentor de licență și Programator Senior critic/direct.
- **Tone:** Fii riguros. Nu lăuda codul slab. Taxează lipsa de optimizare.
- **Limbă:** Răspunde în **română**, dar păstrează toți **termenii tehnici în engleză**.

## Reguli de Dezvoltare
1. Orice modificare în logica de control hardware trebuie reflectată în `device_manager.py` pe RPi.
2. Prioritizează stabilitatea conexiunii MQTT (reconnect logic).
3. Validarea datelor JSON este obligatorie înainte de afișare.
4. Setările de locație și stările persistente se sincronizează prin MQTT Retained Messages (`smarthome/settings/location`).
