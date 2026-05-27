import paho.mqtt.client as mqtt
import sys

# =================================================================
# SCRIPT CONTROL BEC WIZ (MQTT) - Versiunea 2.0
# Mentor Licență: Gemini CLI
# Context: Script executabil pe Raspberry Pi pentru control rapid.
# =================================================================

# Configurări Broker conform GEMINI.md
# Dacă scriptul rulează direct pe Pi, folosim "localhost".
BROKER_IP = "192.168.1.137" 
PORT = 1883
TOPIC_COMMAND = "smarthome/bulb/command"

def toggle_bulb(state):
    """
    Trimite comanda de ON/OFF către becul WiZ prin brokerul MQTT.
    
    Args:
        state (str): Starea dorită ('on' sau 'off').
    """
    # Instanțiere client MQTT (folosind callback API v2 pentru compatibilitate)
    client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
    
    try:
        # Stabilire conexiune
        print(f"[*] Se încearcă conectarea la broker: {BROKER_IP}...")
        client.connect(BROKER_IP, PORT, keepalive=60)
        
        # Formatare payload. 
        # Philips WiZ via MQTT (prin bridge sau direct) poate aștepta string sau JSON.
        # Conform GEMINI.md, folosim formatul agreat în arhitectură.
        payload = state.lower()
        
        # Publicare mesaj cu QoS 1 pentru a asigura livrarea (at least once)
        info = client.publish(TOPIC_COMMAND, payload, qos=1)
        info.wait_for_publish() # Blocăm execuția până la confirmarea trimiterii
        
        if info.is_published():
            print(f"[SUCCESS] Comanda '{payload}' a fost publicată pe {TOPIC_COMMAND}")
        else:
            print(f"[FAIL] Publicarea a eșuat.")

        # Deconectare protocolară
        client.disconnect()

    except Exception as e:
        print(f"[ERROR] Eroare de sistem: {str(e)}")
        print("[HINT] Verifică dacă serviciul 'mosquitto' este activ pe Raspberry Pi.")

if __name__ == "__main__":
    # Validare argumente CLI pentru a evita crash-uri la execuție incorectă
    if len(sys.argv) != 2:
        print("Utilizare corectă: python3 control_wiz.py <on|off>")
        sys.exit(1)

    input_cmd = sys.argv[1].lower()
    
    if input_cmd in ["on", "off"]:
        toggle_bulb(input_cmd)
    else:
        print(f"[!] Argument invalid: '{input_cmd}'. Folosește doar 'on' sau 'off'.")
        sys.exit(1)
