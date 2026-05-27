# Supliment Raport Tehnic - Detalii Implementare și Depanare (Licență)
**Sesiune curentă de optimizare și rezolvare probleme critice**
**Data:** 27 Mai 2026

Acest document completează raportul tehnic anterior, oferind detalii specifice despre erorile identificate și soluțiile inginerești aplicate în cadrul arhitecturii Smart Home Hub (atât pe partea de hardware/backend Python, cât și în interfața Flutter și firmware-ul microcontrolerului).

---

## 1. Depanarea Controlului Hardware: Soluționarea IP-urilor Dinamice (DHCP) în Backend
### A. Problema Semnalată
Dispozitivul de climatizare **Sonoff THR320** raporta corect temperatura și umiditatea în aplicația mobilă, însă releul intern (switch-ul de pornire/oprire a căldurii sau alimentării) nu mai răspundea la comenzile trimise din aplicație.

### B. Analiză Tehnică și Diagnosticare
1. **Rapoartele de Telemetrie (Citirile):** Dispozitivele Sonoff folosesc protocolul **mDNS (Multicast DNS)** pentru a face broadcast în rețea cu starea senzorilor. Serviciul de monitorizare `device_manager.py` (de pe Raspberry Pi) prindea aceste pachete multicast în mod pasiv, indiferent de adresa IP a dispozitivului.
2. **Comenzile de Control (Switch-ul ON/OFF):** Spre deosebire de telemetrie, acționarea releului necesită o conexiune activă **HTTP POST** de tip unicast direct către serverul web integrat pe dispozitivul Sonoff (folosind payload AES criptat).
3. **Cauza defectului:** Adresa IP a Sonoff-ului era salvată static (hardcoded ca `192.168.1.135`) în scriptul python. După o repornire a routerului sau expirarea lease-ului DHCP, routerul a alocat un IP nou dispozitivului. Astfel, cererile HTTP POST eșuau cu erori de tipul `No route to host` (Errno 113) sau `Timeout`, făcând controlul imposibil.

### C. Soluție Implementată (Dynamic IP Resolution)
S-a refactorizat clasa de monitorizare mDNS (`SmartHomeLANMonitor`) în scriptul `device_manager.py`:
- În momentul recepției pachetelor de broadcast (în funcția `add_service`), scriptul extrage în mod dinamic adresa IP curentă din antetul pachetelor mDNS recepționate.
- Variabilele de sesiune `THR_IP` și `S60_IP` sunt actualizate instantaneu în memorie cu noul IP detectat.
- Toate cererile HTTP POST ulterioare folosesc această adresă actualizată în timp real, eliminând definitiv problema IP-urilor dinamice atribuite de DHCP fără a fi nevoie de adrese IP statice configurate manual pe router.

---

## 2. Optimizarea Graficelor de Analiză și Algoritmul de Scalare Dinamică
### A. Problema Semnalată
Graficele istorice pentru temperatură și umiditate prezentau probleme majore de design și scalare:
1. Graficul părea neprofesionist, iar liniile de evoluție depășeau fizic marginile casetei de desenare (clipping/overflow).
2. În situațiile în care valorile senzorilor erau constante (de exemplu, temperatura rămânea fix la 26.8°C), linia evolutivă se prăbușea la baza graficului (axa Y minimă), neexistând repere vizuale sau scalare coerentă.
3. Fluctuațiile infime (zgomotul de citire al senzorului, ex: oscilație între 26.7°C și 26.8°C) erau exagerate vizual pe tot ecranul, creând impresia unor variații climatice dramatice.

### B. Soluție Implementată în Flutter (fl_chart)
S-a reproiectat complet componenta `IstoricDetaliatScreenV2` prin implementarea unui algoritm matematic de scalare dinamică bazat pe un prag minim de variație (`minDelta`):
1. **Definirea plajei minime de scalare (`minDelta`):**
   - Pentru temperatură: `minDelta = 4.0` (grade Celsius).
   - Pentru umiditate: `minDelta = 10.0` (procente %).
2. **Algoritmul de determinare a limitelor axei Y (`minY` și `maxY`):**
   - Se calculează valoarea minimă ($V_{min}$) și maximă ($V_{max}$) din setul de date curent, precum și media lor ($V_{med}$).
   - Se determină delta reală: $Delta_{real} = V_{max} - V_{min}$.
   - Dacă $Delta_{real} < minDelta$ (cazul valorilor constante sau cvasi-constante), limitele graficului se stabilesc simetric în jurul valorii medii folosind plaja minimă:
     $$minY = V_{med} - \frac{minDelta}{2}$$
     $$maxY = V_{med} + \frac{minDelta}{2}$$
   - Dacă variația reală este mai mare decât `minDelta`, se utilizează limitele reale, la care se adaugă un padding de siguranță de 15% în partea superioară și inferioară pentru a preveni lipirea liniei de margini.
3. **Rezultat vizual:** O temperatură constantă de 26.8°C va fi randată ca o linie perfect dreaptă exact la mijlocul ecranului (cu axa Y scalată de la 24.8°C la 28.8°C), oferind o interpretare corectă și profesională a datelor.

---

## 3. Securizarea Conexiunii MQTT pe Microcontrolerul Wemos D1 (ESP8266)
### A. Problema Semnalată
Microcontrolerul Wemos D1 (folosit pentru radarul de mișcare și receptorul IR) nu reușea să se conecteze la brokerul MQTT local Mosquitto rulat pe Raspberry Pi, returnând codul de eroare `rc = -5`.

### B. Analiză și Rezolvare
1. Codul `rc = -5` în biblioteca `PubSubClient` semnifică `Connection Refused: bad user name or password`.
2. Brokerul Mosquitto de pe Raspberry Pi fusese securizat cu autentificare pe bază de credentiale pentru a proteja sistemul. Firmware-ul anterior de pe ESP8266 apela conexiunea simplă `client.connect("Wemos_D1_Node")` fără parametri de securitate.
3. Soluția a constat în actualizarea firmware-ului ESP8266, configurând clientul să transmită credentialele de acces la conectare:
   `client.connect("Wemos_D1_Node", "admin", "beetheleaf123")`
   Aceasta a restabilit instant legătura securizată bidirectională de date.

---

## 4. Integrarea Cheilor SSH și Pregătirea Versionării
Pentru a facilita lucrul colaborativ și publicarea în siguranță a codului sursă pe depozitul de versiuni (Repository-ul public Git), s-a configurat o pereche de chei criptografice de securitate `Ed25519` la nivelul sistemului local de dezvoltare, asigurând un canal securizat pentru operațiunile Git.
