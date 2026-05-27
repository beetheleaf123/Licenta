# Raport Modificări: Integrare Vreme și Coordonate Astronomice

Acest document descrie în detaliu modificările efectuate în cadrul sistemului Smart Home pentru integrarea prognozei meteo și a coordonatelor astronomice (răsărit/apus), utilizând o arhitectură decuplată și sincronizată exclusiv prin protocolul MQTT.

---

## 1. Arhitectura Sistemului (Decoupled Design)

Pentru a asigura stabilitate maximă pe partea de mobile și pentru a evita adăugarea de dependențe native suplimentare (cum ar fi `shared_preferences`), care ar fi putut destabiliza compilarea aplicației Flutter în mediul curent de dezvoltare, am implementat o soluție bazată pe backend-ul central:

1. **Stocarea persistentă pe RPi (SQLite)**: Setările de locație ale utilizatorului (oraș, latitudine, longitudine, orele de răsărit și apus) sunt stocate persistent pe Raspberry Pi într-o tabelă generală `settings`.
2. **Sincronizare State (MQTT Retained Messages)**:
   - La conectare, aplicația Flutter subscrie la topicul `smarthome/settings/location`.
   - Scriptul `device_manager.py` publică automat setările stocate pe acest topic cu flag-ul `retain=True`.
   - Astfel, de fiecare dată când aplicația mobilă pornește sau se reconectează la brokerul MQTT, aceasta primește instant ultima locație salvată și își actualizează UI-ul fără a fi nevoie de stocare locală pe dispozitiv.
3. **Serviciu Meteo Extern (Open-Meteo APIs)**:
   - Căutarea orașelor: Folosește Open-Meteo Geocoding API (apel direct HTTP `GET` fără API Key).
   - Prognoza pe 5 zile: Folosește Open-Meteo Forecast API pentru a prelua temperaturile min/max, condițiile meteo (coduri WMO), șansa maximă de precipitații (rain chance) și coordonatele de răsărit/apus.

---

## 2. Modificări pe Raspberry Pi (Backend logic)

Fișierul modificat: [device_manager.py](file:///Z:/home/mrz/HubMQTT/device_manager.py)

### A. Integrarea în Baza de Date SQLite
Am configurat tabela `settings` pentru a stoca detalii despre locație sub formă de perechi cheie-valoare:
- `city_name`: Numele orașului selectat (ex. "București").
- `latitude` / `longitude`: Coordonatele geografice utilizate pentru interogarea API-ului meteo.
- `sunrise` / `sunset`: Timpii astronomici calculați pentru ziua curentă de către API-ul meteo, salvați pe RPi pentru a putea fi utilizați ulterior în regulile de automatizare locale (ex: pornirea luminilor exterioare la apus).

### B. Gestionarea Evenimentelor MQTT
Am adăugat logica de procesare a mesajelor pe topicul `smarthome/settings/location`:
- La pornire, funcția `publish_stored_location()` interoghează baza de date SQLite, construiește un payload JSON cu datele locației și le publică cu `retain=True`.
- La recepționarea unui mesaj nou de la Flutter pe același topic (în urma selectării unui oraș nou de către utilizator), callback-ul `on_message` extrage coordonatele și orele astronomice și le stochează în SQLite.

---

## 3. Modificări în Aplicația Flutter (Frontend UI & Logic)

Fișierul modificat: [main_v2CLAUDE.dart](file:///e:/smart_app/flutter_application_1/lib/main_v2CLAUDE.dart)

### A. Corectarea erorilor de compilare
Am rezolvat defectele semnalate la compilarea anterioară:
1. **HTTP Import**: Am adăugat pachetul `http` (`import 'package:http/http.dart' as http;`) necesar pentru interogarea serviciului web Open-Meteo.
2. **Container constraints**: În dialogul `CitySearchDialog`, am înlocuit parametrul invalid `maxHeight` din constructorul `Container` cu un obiect de constrângere standard `constraints: const BoxConstraints(maxHeight: 450)`.
3. **State Management**: Am definit metodele lipsă (`_fetchWeatherForecast`, `_buildWeatherCard`, etc.) în interiorul stării `_DashboardScreenV2State`.

### B. Integrare API & Geocoding
- **`CitySearchDialog`**: O casetă de dialog în care utilizatorul poate introduce numele unui oraș. Dialogul face un request HTTP la Open-Meteo Geocoding, primește primele 5 sugestii cu județ/țară și le afișează într-o listă. La click, transmite coordonatele înapoi la dashboard.
- **`_fetchWeatherForecast()`**: Descarcă asincron prognoza meteo pentru următoarele 5 zile și datele curente pe baza latitudinii și longitudinii primite.
- **`_updateLocation()`**: Metodă centralizată care apelează `_fetchWeatherForecast()` și, după ce obține datele astronomice actualizate (răsărit/apus), publică întregul set pe topicul MQTT `smarthome/settings/location` pentru sincronizare cu Raspberry Pi.

### C. UI Modern: WEATHER ENGINE
Am creat un widget premium integrat direct în Dashboard:
- **Design Elegant**: Gradient premium de culoare indigo/deep blue care conferă un aspect high-tech și sporește contrastul informațiilor.
- **Micro-interacțiuni**: Buton de schimbare a locației integrat organic și o listă orizontală fluidă pentru prognoza pe 5 zile.
- **WMO Code Mapping**: Funcție dedicată (`_getWmoDetails`) care convertește codurile standard WMO (World Meteorological Organization) în descrieri prietenoase în limba română (ex. "Senin", "Partial Noros", "Averse de ploaie") și asociază pictograme animate și culori specifice fiecărei stări meteorologice.
- **Astronomical Info**: Afișarea orelor de răsărit și apus preluate din prognoza meteo, lângă indicatorul șansei de ploaie (rain chance).

---

## 4. Validare și Teste

Compilarea debug a APK-ului a fost realizată cu succes:
```bash
Running Gradle task 'assembleDebug'...                             46.4s
√ Built build\app\outputs\flutter-apk\app-debug.apk
```
Acest lucru demonstrează rezolvarea integrală a problemelor de tipărire statică a tipurilor și a importurilor lipsă. Proiectul este acum stabil și pregătit pentru rulare.
