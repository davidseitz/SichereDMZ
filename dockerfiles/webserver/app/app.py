import logging
import os
import secrets
from flask import Flask, render_template, request, redirect, session, url_for, send_file, abort
from flask_session import Session  # <--- REQUIRED for server-side sessions
from captcha.image import ImageCaptcha
from functools import wraps
import pymysql
import bcrypt
import io

app = Flask(__name__)

# --- SECURITY CONFIGURATION ---
app.secret_key = os.getenv("FLASK_SECRET", "super-secure-dev-secret-key")

# 1. Configure Server-Side Sessions
# This stores session data in the /flask_session folder inside the container
# The browser only gets a Session ID, not the data itself.
app.config["SESSION_TYPE"] = "filesystem" 
app.config["SESSION_FILE_DIR"] = "./flask_session"
app.config["SESSION_PERMANENT"] = False
app.config["SESSION_USE_SIGNER"] = True
Session(app)

# 2. Allowed Host Header (Must match WAF config)

# Hostkonfiguration
ALLOWED_HOST = "web.sun.dmz"

# Database Configuration
DB_HOST = os.getenv("DB_HOST", "10.10.40.2")
DB_USER = os.getenv("DB_USER", "webuser")
DB_PASS = os.getenv("DB_PASS", "webpass")
DB_NAME = os.getenv("DB_NAME", "webapp")

# Logging (Same as before)
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger("webapp")

def get_db_conn():
    return pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME, cursorclass=pymysql.cursors.DictCursor, autocommit=True)

def init_db():
    """
    Initialisiert das Datenbankschema. 
    Wird vom externen Setup-Skript aufgerufen, um sicherzustellen, dass die Tabellen existieren.
    """
    app.logger.info("INIT_DB_START: Executing Database Schema Initialization.")
    conn = None
    try:
        conn = get_db_conn()
        with conn.cursor() as cur:
            # Erstellt die Benutzertabelle, falls sie noch nicht existiert
            cur.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    username VARCHAR(50) UNIQUE NOT NULL,
                    password_hash VARCHAR(255) NOT NULL
                )
            """)
        app.logger.info("INIT_DB_SUCCESS: Database schema successfully verified/created.")
    except pymysql.err.OperationalError as e:
        app.logger.critical(f"INIT_DB_FAILURE: Could not initialize database schema. Connection failed: {e}")
        raise
    except Exception as e:
        app.logger.error(f"INIT_DB_FAILURE: An unexpected error occurred during DB schema initialization: {e}")
        raise
    finally:
        if conn:
            conn.close()


# --- DEKORATOR ZUR PRÜFUNG DER DB-VERFÜGBARKEIT (Dynamische Prüfung) ---
def check_db_availability(f):
    """Prüft die DB-Verbindung dynamisch vor jedem geschützten Request."""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        conn = None
        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute("SELECT 1") 
            # Wenn erfolgreich, fahre mit der Route fort
            return f(*args, **kwargs)
        except pymysql.err.OperationalError as e:
            # Fängt Fehler bei Verbindung, Authentifizierung oder Netzwerk
            app.logger.warning(f"DB_CHECK_FAILED: Database connection failed during request to {request.path}. Returning 503.")
            return render_template("error_init.html"), 503 
        except Exception as e:
            # Fängt andere unerwartete Fehler
            app.logger.error(f"DB_CHECK_ERROR: An unexpected error occurred during DB check for {request.path}: {e}")
            return render_template("error_500.html", error_message="Interner Fehler bei der Datenbankprüfung."), 500
        finally:
            if conn:
                conn.close() # Stelle sicher, dass die Verbindung geschlossen wird
    return decorated_function


# --- DEKORATOR ZUR PRÜFUNG DER AUTHENTIFIZIERUNG ---
def login_required(f):
    """Leitet zu signin um, wenn der Benutzer nicht in der Session ist."""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if "user" not in session:
            # Log the attempt to access a restricted page
            app.logger.warning(f"UNAUTHORIZED_ACCESS: Attempted access to protected route {request.path} by anonymous user from {request.remote_addr}.")
            return redirect(url_for('signin'))
        return f(*args, **kwargs)
    return decorated_function

# --- BEFORE REQUEST ---

@app.before_request
def check_host_header():
    # The Host header is available in request.headers['Host']
    # The header value might include the port
    # so we should split it to get only the hostname.
    host_header = request.headers.get('Host')
    
    if host_header:
        # Get the hostname part (strip port if present)
        hostname = host_header.split(':')[0]
        
        if hostname != ALLOWED_HOST:
            # Equivalent to NGINX's return 444 (close connection), 
            # we can return an immediate 400 or 403 response, or 
            # simply abort with 404 to provide no useful info..
            app.logger.warning(f"HOST_CHECK_FAILED: Missing Host header from {request.remote_addr}. Blocking.")
            abort(403) # Return a 403 Forbidden response

# --- ROUTEN ---

@app.route("/")
@check_db_availability
def index():
    if "user" in session:
        return redirect(url_for('dashboard'))
    return render_template("index.html")

@app.route("/auth")
@check_db_availability
def auth_choice():
    return render_template("auth_choice.html")

# --- New Route to Serve the Image ---

@app.route("/captcha/image")
def captcha_image():
    # Generate random text (Using alphanumeric to avoid confusion)
    # Using 'secrets' is cryptographically stronger than 'random'
    image_text = secrets.token_hex(3).upper() # Generates ~6 chars
    
    # STORE SECURELY: 
    # This saves the answer in ./flask_session/[session_id] on the SERVER.
    # The client cannot see this value.
    session["captcha_answer"] = image_text
    
    # Generate image
    image = ImageCaptcha(width=280, height=90)
    data = image.generate(image_text)
    
    return send_file(data, mimetype="image/png")

@app.route("/signup", methods=["GET", "POST"])
def signup():
    if request.method == "POST":
        # --- DEFENSE LAYER 1: REPLAY PROTECTION ---
        # Retrieve the answer and IMMEDIATELY remove it from the session.
        # If the user reloads or an attacker replays the request, 'real_answer' will be None.
        real_answer = session.pop("captcha_answer", None)
        user_answer = request.form.get("captcha_answer", "").upper()

        # --- DEFENSE LAYER 2: VALIDATION LOGIC ---
        if not real_answer:
            logger.warning(f"SECURITY: Replay attack or expired session detected from {request.remote_addr}")
            return render_template("signup.html", error="Session expired. Please reload the captcha.")

        # Use constant time comparison to prevent timing attacks
        if not secrets.compare_digest(real_answer, user_answer):
            logger.debug(f"CAPTCHA_FAIL: Expected '{real_answer}', got '{user_answer}' from {request.remote_addr}")
            logger.info(f"CAPTCHA_FAIL: Incorrect code from {request.remote_addr}")
            return render_template("signup.html", error="Incorrect security code.")

        # --- DEFENSE LAYER 3: RESOURCE PROTECTION ---
        # Only NOW do we perform expensive operations (Hashing/DB)
        
        username = request.form.get("username")
        password = request.form.get("password")

        if not username or not password or len(password) < 8:
            return render_template("signup.html", error="Invalid input.")

        # Expensive Bcrypt operation (Only runs if human is verified)
        pw_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute("INSERT INTO users (username, password_hash) VALUES (%s, %s)", 
                            (username, pw_hash.decode('utf-8')))
            return redirect(url_for('signin'))
        except pymysql.err.IntegrityError:
            return render_template("signup.html", error="Username taken.")
        except Exception as e:
            logger.error(f"DB Error: {e}")
            return render_template("signup.html", error="System error.")
        finally:
            if 'conn' in locals(): conn.close()

    return render_template("signup.html")


@app.route("/signin", methods=["GET", "POST"])
@check_db_availability
def signin():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        remote_addr = request.remote_addr
        
        if not username or not password:
            app.logger.info(f"SIGNIN_FAILED: Missing fields during attempt from {remote_addr}.")
            return render_template("signin.html", error="Alle Felder sind erforderlich.")

        user = None
        conn = None
        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute("SELECT password_hash FROM users WHERE username=%s", (username,))
                user = cur.fetchone()
            conn.close()
        except Exception as e:
            app.logger.error(f"SIGNIN_ERROR: Database error during signin for '{username}' from {remote_addr}: {e}")
            return render_template("error_500.html", error_message="Fehler beim Anmeldevorgang."), 500

        # Prüfen, ob Benutzer existiert und Passwort übereinstimmt
        if user and bcrypt.checkpw(password.encode('utf-8'), user["password_hash"].encode('utf-8')):
            session["user"] = username
            app.logger.info(f"SIGNIN_SUCCESS: User '{username}' logged in from {remote_addr}.")
            return redirect(url_for('dashboard'))
        else:
            app.logger.warning(f"SIGNIN_FAILED: Invalid credentials attempt for username '{username}' from {remote_addr}.")
            return render_template("signin.html", error="Ungültige Anmeldedaten.")

    return render_template("signin.html")

@app.route("/dashboard")
@check_db_availability
@login_required
def dashboard():
    # Log successful access to a protected page after authentication
    app.logger.info(f"ACCESS_GRANTED: User '{session['user']}' accessed dashboard.")
    return render_template("dashboard.html", user=session["user"])

@app.route("/logout")
def logout():
    user = session.get("user")
    session.clear()
    if user:
        app.logger.info(f"USER_LOGOUT: User '{user}' logged out.")
    else:
        app.logger.info(f"USER_LOGOUT: Anonymous session cleared (was not authenticated).")
    return redirect(url_for('index'))

# --- FEHLER-HANDLER ---

@app.errorhandler(503)
def service_unavailable_error(e):
    app.logger.critical(f"HTTP_ERROR: 503 Service Unavailable triggered at {request.path}.")
    return render_template("error_init.html"), 503

@app.errorhandler(404)
def page_not_found(e):
    app.logger.warning(f"HTTP_ERROR: 404 Not Found for URL {request.url} from {request.remote_addr}.")
    return render_template("error_404.html"), 404

@app.errorhandler(500)
def internal_server_error(e):
    # Flask logs the traceback automatically; here we log the final handler
    app.logger.error(f"HTTP_ERROR: 500 Internal Server Error triggered at {request.path}.")
    return render_template("error_500.html", error_message="Ein interner Serverfehler ist aufgetreten."), 500


if __name__ == "__main__":
    # In einem Gunicorn/Worker-Setup wird dieser Block nicht ausgeführt. 
    # Die Initialisierung sollte über das externe Skript erfolgen, das init_db() aufruft.
    pass