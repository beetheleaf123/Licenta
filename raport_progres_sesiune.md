# Raport de Progres: Sesiune de Dezvoltare Smart Home Hub

Acest document sumarizează modificările aduse codului, verificările efectuate pe backend și argumentația arhitecturală dezvoltată în cadrul acestei sesiuni. Materialul este structurat pentru a fi integrat direct în lucrarea de licență.

## 1. Corectarea Interfeței Grafice (Flutter) - Sincronizarea Stării

**Problema identificată:**
În ecranul de notificări (`notifications_screen.dart`), butonul flotant (Floating Action Button) de adăugare a unei noi alerte de prag ("ALERTĂ NOUĂ") nu devenea vizibil la comutarea pe tab-ul corespunzător. Problema era cauzată de lipsa unui mecanism de notificare a instanței `Scaffold` pentru a forța reconstrucția (rebuild) la modificarea indexului din `TabController`.

**Soluția implementată:**
S-a adoptat o abordare optimizată pentru performanță folosind clasa `AnimatedBuilder`. Butonul flotant a fost încapsulat în acest builder, setând `animation: _tabController`. Astfel, reconstrucția se limitează strict la widget-ul butonului, evitând un `setState` global costisitor la fiecare navigare între tab-uri.

## 2. Verificarea Logicii de Evaluare a Pragurilor (Backend Python)

S-a analizat modulul `device_manager.py` (rulând pe Raspberry Pi) pentru a confirma corectitudinea logicii de declanșare a alertelor.

**Concluzii validare backend:**
*   **Implementarea Mașinii de Stare (State Machine):** S-a confirmat că funcția `evaluate_alerts` utilizează un dicționar de stare (`alert_hysteresis_state`) pentru fiecare alertă (tranzitând între `READY` și `TRIGGERED`). Aceasta previne fenomenul de "alert fatigue" (spam), asigurând trimiterea unei singure notificări la depășirea pragului.
*   **Histerezis Simetric și Asimetric:** Backend-ul suportă ambele moduri de funcționare, configurate din UI:
    *   *Mod Simplu (Simetric):* Punctul de resetare este dedus pe baza operatorului (`> / <`) scăzând sau adunând valoarea histerezisului la pragul setat.
    *   *Mod Avansat (Asimetric):* Utilizează valorile explicite `lower_limit` și `upper_limit` trimise din aplicație, permițând definirea precisă a benzii de declanșare și resetare.
*   **Persistență:** Datele introduse prin formular sunt preluate corect de pe topicul MQTT `smarthome/alerts/save` și persistate în baza de date `smart_home.db`.

## 3. Maparea Arhitecturii Actulizate a Sistemului

S-a generat o schemă arhitecturală actualizată (prin cod Mermaid) care modelează cu acuratețe stadiul curent al ecosistemului:

*   **Subsistemul AI:** S-a evidențiat integrarea `ai_engine.py` (Luffy Chat Engine, utilizând API-ul Google Gemini `gemini-2.5-flash`) care interacționează cu componentele fizice prin **Function Calling**, având acces de citire și scriere la istoricul conversațiilor (`smart_home.db`).
*   **Sistemul de Notificări Decuplate:** S-a mapat modulul `notification_service.py`, subliniind natura sa neblocantă (non-blocking I/O) obținută prin delegarea apelurilor HTTP către serverul NTFY către fire de execuție secundare (daemon threads).
*   **Separarea Local-Cloud:** S-a definit clar delimitarea dintre procesarea locală securizată (controlul releelor și prizelor Sonoff via payload AES-128 și al becului WiZ via UDP local) și apelurile externe către API-urile cloud (Gemini, Open-Meteo, Server NTFY public/self-hosted).

## 4. Structurarea Argumentației Academice

S-a definit o expunere structurată destinată prezentării proiectului în fața cadrului didactic coordonator. Aspectele cheie de evidențiat includ:

1.  **Arhitectura Orientată pe Evenimente (Event-Driven):** Utilizarea broker-ului MQTT pentru decuplarea logică a senzorilor, UI-ului și logicii de control.
2.  **Privacy și Edge Computing:** Beneficiile executării logicii critice și a criptării direct pe un nod de margine (Raspberry Pi), eliminând latența și dependența de platforme comerciale închise (ex. eWeLink).
3.  **Extensibilitatea Sistemului:** Arhitectura modulară ce permite rularea simultană a unor servicii eterogene (server de chat AI, manager de rutine, serviciu notificări) cuplate liber prin intermediul bazei de date SQLite.
