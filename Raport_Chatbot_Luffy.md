# Raport de Implementare: Integrare Asistent AI „Luffy” în Smart Home Hub

Acest raport oferă o descriere academică și tehnică detaliată a integrării chatbot-ului AI numit **„Luffy”** în cadrul sistemului Smart Home Hub, acoperind modificările aduse pe Raspberry Pi și în aplicația Flutter.

---

## 1. Obiectivele Proiectului
- **Interfață Conversațională**: Permiterea controlului casei inteligente prin limbaj natural în limba română.
- **Function Calling**: Utilizarea capabilităților Gemini API pentru a apela automat funcții locale (interogare senzori live, citire istoric SQLite și trimitere comenzi hardware).
- **Vizualizare Date**: Generarea on-the-fly de grafice inline (`fl_chart`) direct în interiorul ferestrei de chat la solicitarea utilizatorului.
- **Securitate și Performanță**: Păstrarea cheilor API în siguranță pe RPi și execuția asincronă a apelurilor AI în thread-uri separate pentru a menține stabilitatea buclei MQTT.

---

## 2. Arhitectura Sistemului (Flow de Date)

Sistemul utilizează o topologie decuplată bazată pe **MQTT** ca magistrală de mesaje, intermediată de un proxy local pe RPi care apelează API-ul Google Gemini:

```
[ Flutter Client ] 
       │ (smarthome/chat/user_message)
       ▼
[ MQTT Broker (Mosquitto) ]
       │ (smarthome/chat/user_message)
       ▼
[ chat_api.py (RPi Handler) ] ──(async thread)──► [ ai_engine.py ] ──► [ Gemini API (Cloud) ]
       │                                                 │
       │ (Salvare în chat_history DB)                    ├─► [ get_live_sensor_data() ] ─► Volatile Memory
       │                                                 ├─► [ get_sensor_history() ] ──► SQLite DB
       ▼                                                 └─► [ control_device() ] ──────► Sonoff/Wiz Commands
[ chat_api.py (RPi Handler) ] 
       │ (smarthome/chat/bot_response)
       ▼
[ MQTT Broker (Mosquitto) ]
       │ (smarthome/chat/bot_response)
       ▼
[ Flutter UI (ChatScreen) ] ──► Randează LineChart sau Mesaj Text
```

---

## 3. Descrierea Tehnică a Componentelor Backend (RPi)

Toate scripturile rulează în mediul virtual Python `/home/mrz/HubMQTT/smarthome_env` pe Raspberry Pi.

### A. Modulul de Inteligență AI: `ai_engine.py`
Creat de la zero la `/home/mrz/HubMQTT/ai_engine.py` folosind noul SDK **`google-genai`** (v2.7.0):
- **Gestiunea Sesiunilor**: Reține instanțele de chat în memorie (`_session_chats`) asociate cu un ID de sesiune unic transmis din Flutter pentru a păstra contextul conversației.
- **Function Calling Loop**: Pentru a garanta compatibilitatea și stabilitatea în noul SDK `google-genai`, s-a implementat o buclă manuală de parsare a răspunsurilor de tip `function_calls`. Când modelul (setat pe `gemini-2.5-flash`) propune o acțiune, scriptul o rulează local, colectează rezultatul într-un obiect `types.Part.from_function_response` și îl re-transmite asistentului până când acesta oferă un răspuns final.
- **Funcții Expuse (Tools)**:
  1. `get_live_sensor_data()`: Citește stările senzorilor direct din memoria `device_manager.py`.
  2. `get_sensor_history(sensor, interval)`: Execută interogări în tabela SQLite `istoric_senzori`. Pentru perioade scurte (3h, 24h) face downsampling în Python la maximum 100 de puncte. Pentru perioade lungi (7d, all) rulează agregări direct în SQL (`AVG`, `MIN`, `MAX` grupate pe zi).
  3. `control_device(device, state)`: Trimite comenzi către bec, priza S60 sau releul THR.
- **Formatare Grafic**: Dacă utilizatorul cere o vizualizare grafică, promptul de sistem instruiește AI-ul să plaseze datele formatate JSON la sfârșitul răspunsului său, sub etichetele `[GRAPH_DATA] ... [/GRAPH_DATA]`.

### B. Managerul de Chat MQTT: `chat_api.py`
Creat la `/home/mrz/HubMQTT/chat_api.py`:
- Ascultă mesajele de pe topicul `smarthome/chat/user_message`.
- Trimite instant stări de tip `typing` și `idle` pe topicul `smarthome/chat/status` pentru a anima interfața clientului.
- Folosește `asyncio.to_thread` pentru a trimite cererile către `ai_engine.py` pe un thread separat, lăsând bucla asincronă de la Paho-MQTT liberă (previne timeout-urile).
- Salvează istoricul mesajelor în tabela SQLite nouă numită `chat_history` (coloane: `id`, `session_id`, `role`, `content`, `chart_data`, `timestamp`).

### C. Integrarea în Serverul Central: `device_manager.py`
Modificat la `/home/mrz/HubMQTT/device_manager.py`:
- Actualizează permanent variabilele globale de telemetrie (`current_temperature`, `current_humidity`, `current_lux`, `bulb_status`, `plug_status`, `plug_power`, `thr_status`) la primirea datelor de la mDNS/Zeroconf sau Wemos.
- Expune aceste variabile prin Dependency Injection către `ai_engine.py` (pentru a evita importurile circulare).
- Pornește un task asincron la boot în event-loop-ul principal (`init_bulb_status()`) pentru a interoga starea inițială a becului WiZ de pe rețeaua locală.

---

## 4. Descrierea Tehnică a Componentelor Frontend (Flutter)

Codul client a fost dezvoltat în limbajul Dart, folosind librăriile `fl_chart` și `mqtt_client`.

### A. Modelul și Serviciul: `chat_service.dart`
Creat la `lib/chat_service.dart`:
- Definește structura `ChatMessage` care suportă mesaje text, mesaje de tip typing indicator și structuri opționale `chartData`.
- Se abonează la topicurile MQTT `bot_response` și `status` prin intermediul instanței preexistente de `MqttServiceV2`.
- Expune un Stream reactiv (`messagesStream`) pentru a notifica automat paginile de UI la primirea de date noi.

### B. Interfața de Conversație: `chat_screen.dart`
Creată la `lib/chat_screen.dart` cu design premium adaptat la Dark Mode (Indigo/Teal):
- **Animație Typing**: S-a implementat o clasă `_TypingIndicator` care animează în mod continuu opacitatea și dimensiunea a 3 puncte prin intermediul unui `AnimationController` nativ.
- **Grafice Inline**: Dacă asistentul trimite un mesaj care conține `chartData`, se desenează o casetă grafică `LineChart` direct în interiorul bulei de chat.
- **Algoritmul de Histerezis (minDelta)**:
  Dacă ecartul de date ($\Delta = V_{max} - V_{min}$) este mai mic decât un prag critic predefinit ($4.0^\circ\text{C}$ pentru temperatură și $10\%$ pentru umiditate), limitele Y ale graficului sunt calculate simetric în jurul valorii medii:
  
  $$minY = V_{med} - \frac{\Delta_{critica}}{2}$$
  $$maxY = V_{med} + \frac{\Delta_{critica}}{2}$$
  
  Acest lucru previne ca variații infime de zecimi de grad să fie afișate sub formă de oscilații abrupte și dramatice. Dacă delta depășește pragul, se adaugă un padding vizual standard de 15% pe margini.
- **Imagine de Avatar locală**: Încărcarea avatarului din fișierul `luffy.png` cu un mecanism `errorBuilder` care face automat fallback la o pictogramă robotică standard dacă fișierul lipsește din build.
- **Quick Actions**: Butoane rapide de control („Cum e temperatura?”, „Stinge becul”, etc.) plasate direct deasupra input-bar-ului.

### C. Butonul Dashboard: `main_v2CLAUDE.dart`
Modificat la `lib/main_v2CLAUDE.dart`:
- Înlocuirea butonului de „Debugging” singular cu un rând simetric format din 2 butoane (`Debugging` și `Luffy Chat`).
- S-a creat widget-ul ajutător `_buildGradientNavigationButton` care oferă un design cu gradient Verde-Teal (`[Color(0xFF0D9488), Color(0xFF0F766E)]`) și text/iconițe albe cu umbre fine.

---

## 5. Istoric Depanare și Rezoluții Cheie

Pe parcursul dezvoltării, s-au rezolvat următoarele probleme critice:
1. **Erori de Import (google.generativeai)**: Pachetul vechi de Python a fost înlocuit pe RPi cu noul SDK oficial `google-genai` (2.7.0). Codul a fost rescris complet pentru a se adapta noilor metode API (cum ar fi `client.chats.create` în loc de `GenerativeModel.start_chat`).
2. **SyntaxError (global variables)**: În `device_manager.py`, declarațiile `global current_lux` din blocuri condiționale separate generau erori de compilare. Declarația a fost mutată la începutul funcției `on_message()`.
3. **Erori de Environment (Systemd)**: Directiva `Environment` era definită greșit sub secțiunea `[Install]` a fișierului service din RPi. Aceasta a fost mutată sub secțiunea `[Service]`, permițând citirea corectă a cheii API.
4. **Resurse Epuizate (Billing API - 429)**: Utilizatorul a întâmpinat blocaje pe billing-ul Google Cloud. Soluția a fost generarea unei noi chei API într-un proiect separat din AI Studio fără Billing activat, care folosește în mod implicit Free Tier-ul gratuit.
5. **Erori 404 Model Not Found**: SDK-ul nou trimitea cereri către endpoint-uri incompatibile cu modelul vechi. Modelul utilizat a fost modificat în `gemini-2.5-flash`.
6. **Integrare Resurse Flutter (luffy.png)**: Imaginea de avatar a fost mutată în rădăcina proiectului, declarată ca asset în `pubspec.yaml` și actualizată în codul Dart ca `'luffy.png'`.

---

## 6. Starea Git (Push Realizat)
Modificările din folderul `lib`, împreună cu resursele adăugate, au fost înregistrate și trimise pe repository-ul GitHub pe branch-ul **`BranchUICentrat`**:
```bash
git add lib/main_v2CLAUDE.dart lib/chat_screen.dart lib/chat_service.dart pubspec.yaml luffy.png
git commit -m "feat: add Luffy AI chatbot integration with Gemini API and inline charts"
git push
```
