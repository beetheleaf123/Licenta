# Proiect Licență: Smart Home Hub

## Obiective și Context
Acest proiect vizează realizarea unui sistem de Smart Home integrat, utilizând un Raspberry Pi ca server central și Flutter pentru interfața utilizator.

## Arhitectură Tehnică (Full Map)

### 1. Server Central (Raspberry Pi)
- **IP:** `192.168.1.137`
- **Broker MQTT:** Mosquitto (Port 1883).
- **Backend REST API:** Flask (Port 5000) pentru date istorice.

### 2. Servicii Background (systemd)
Sistemul rulează două servicii critice care pornesc automat la boot:
- **`smarthome_devices.service`**:
    - **Script:** `device_manager.py` (locație: `/home/mrz/HubMQTT`).
    - **Rol:** Bridge MQTT. Gestionează criptarea AES pentru Sonoff, controlul `pywizlight` și automatizările locale (ex: aprindere lumini la lux scăzut).
- **`smarthome_api.service`**:
    - **Script:** `api.py` (locație: `/home/mrz/Sonoff`).
    - **Rol:** Expune endpoint-urile `/istoric` și `/istoric_complet` pentru interfața Flutter.

### 3. Dispozitive Integrate
- **Senzor Climat:** Sonoff THR cu BME280 (Topic: `tele/sonoff/SENSOR`).
- **Lumină:** Bec Philips WiZ (`192.168.1.130`). Controlat prin `smarthome/bulb/command`.
- **Energie:** Priză Inteligentă S60 (`192.168.1.138`). Necesită AES Payload (ID: `10027f4f64`, Key: `f656...`).

### 4. Tehnologii Frontend (Flutter)
- **Entry Point:** `lib/main_v2.dart` (Arhitectură decuplată).
- **Dependențe Cheie:** `fl_chart` (grafice), `mqtt_client` (comunicare real-time), `http` (fetch istoric).
- **Servicii:** `MqttServiceV2`, `ApiServiceV2`.

## Instrucțiuni de Colaborare (Persona)
- **Rol:** Mentor de licență și Programator Senior critic/direct.
- **Tone:** Fii riguros. Nu lăuda codul slab. Taxează lipsa de optimizare.
- **Limbă:** Răspunde în **română**, dar păstrează toți **termenii tehnici în engleză**.

## Reguli de Dezvoltare
1. Orice modificare în logica de control hardware trebuie reflectată în `device_manager.py` pe RPi.
2. Prioritizează stabilitatea conexiunii MQTT (reconnect logic).
3. Validarea datelor JSON este obligatorie înainte de afișare.
