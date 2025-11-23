import logging
from flask import Flask, render_template, request, redirect, session, url_for
import pymysql
import bcrypt
import os
from functools import wraps
from time import sleep # Not strictly needed, but kept for completeness of original structure

# --- Application Setup ---
app = Flask(__name__)
# WICHTIG: Dies sollte in einer Produktionsumgebung sicher gesetzt werden.
app.secret_key = os.getenv("FLASK_SECRET", "super-secure-dev-secret-key-01234") 

# Datenbankkonfiguration
DB_HOST = os.getenv("DB_HOST", "10.10.40.2")
DB_PORT = int(os.getenv("DB_PORT", 3306))
DB_USER = os.getenv("DB_USER", "webuser")
DB_PASS = os.getenv("DB_PASS", "webpass")
DB_NAME = os.getenv("DB_NAME", "webapp")

# --- LOGGING SETUP ---
LOG_FILE = "/var/log/webapp.log"

# Ensure log directory exists (important for container environments)
log_dir = os.path.dirname(LOG_FILE)
if not os.path.exists(log_dir):
    try:
        os.makedirs(log_dir, exist_ok=True)
    except Exception as e:
        # Print to stdout/stderr since logging might not be fully functional yet
        print(f"Warning: Could not create log directory {log_dir}. Logging might fail: {e}")

# Set up the basic logger format
logging.basicConfig(level=logging.INFO)

# File handler for the security log file
file_handler = logging.FileHandler(LOG_FILE)
file_handler.setLevel(logging.INFO)
# Define a robust format for security logging
file_handler.setFormatter(logging.Formatter(
    '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
))

# Add the file handler to the Flask application logger
app.logger.addHandler(file_handler)
app.logger.info("Application logging initialized and outputting to %s.", LOG_FILE)
# --- END LOGGING SETUP ---


def get_db_conn():
    """Gibt eine Datenbankverbindung zurück. Kann pymysql.err.OperationalError auslösen."""
    try:
        return pymysql.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASS,
            database=DB_NAME,
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=True
        )
    except pymysql.err.OperationalError as e:
        # Log this as a critical event as it affects application availability
        app.logger.critical(f"DB_CONNECTION_FAILED: Attempt to connect to DB at {DB_HOST}:{DB_PORT} failed. Error: {e}")
        raise # Re-raise the exception


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

@app.route("/signup", methods=["GET", "POST"])
@check_db_availability
def signup():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        if not username or not password:
            app.logger.info(f"SIGNUP_FAILED: Missing fields for username '{username}'.")
            return render_template("signup.html", error="Alle Felder sind erforderlich.")
        
        if len(password) < 8:
            app.logger.info(f"SIGNUP_FAILED: Password too short for username '{username}'.")
            return render_template("signup.html", error="Das Passwort muss mindestens 8 Zeichen lang sein.")

        pw_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
        conn = None 

        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute("INSERT INTO users (username, password_hash) VALUES (%s, %s)", 
                            (username, pw_hash.decode('utf-8')))
            app.logger.info(f"SIGNUP_SUCCESS: New user registered: '{username}'.")
        except pymysql.err.IntegrityError:
            app.logger.warning(f"SIGNUP_FAILED: Username already exists: '{username}'.")
            return render_template("signup.html", error="Benutzername existiert bereits. Bitte wählen Sie einen anderen.")
        except Exception as e:
             app.logger.error(f"SIGNUP_ERROR: Database error during signup for '{username}': {e}")
             return render_template("error_500.html", error_message="Fehler bei der Registrierung."), 500
        finally:
            if conn:
                conn.close()

        return redirect(url_for('signin'))

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