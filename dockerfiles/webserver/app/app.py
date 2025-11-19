from flask import Flask, render_template, request, redirect, session, url_for
import pymysql
import bcrypt
import os
from functools import wraps
from time import sleep

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


def get_db_conn():
    """Gibt eine Datenbankverbindung zurück. Kann pymysql.err.OperationalError auslösen."""
    return pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True
    )

def init_db():
    """
    Initialisiert das Datenbankschema. 
    Wird vom externen Setup-Skript aufgerufen, um sicherzustellen, dass die Tabellen existieren.
    """
    print("Executing Database Schema Initialization...")
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
        print("Database schema successfully verified/created.")
    except pymysql.err.OperationalError as e:
        print(f"ERROR: Could not initialize database schema. Connection failed: {e}")
        # Wir lassen den Fehler hier durch, damit das externe Skript ihn fangen kann.
        raise
    except Exception as e:
        print(f"ERROR: An unexpected error occurred during DB schema initialization: {e}")
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
            # Versuch, eine Verbindung herzustellen und eine einfache Abfrage durchzuführen.
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute("SELECT 1") 
            # Wenn erfolgreich, fahre mit der Route fort
            return f(*args, **kwargs)
        except pymysql.err.OperationalError as e:
            # Fängt Fehler bei Verbindung, Authentifizierung oder Netzwerk
            print(f"Database connection failed during request: {e}")
            return render_template("error_init.html"), 503 
        except Exception as e:
            # Fängt andere unerwartete Fehler
            print(f"An unexpected error occurred during DB check: {e}")
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
            return render_template("signup.html", error="Alle Felder sind erforderlich.")
        
        if len(password) < 8:
            return render_template("signup.html", error="Das Passwort muss mindestens 8 Zeichen lang sein.")

        pw_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
        conn = None 

        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute("INSERT INTO users (username, password_hash) VALUES (%s, %s)", 
                            (username, pw_hash.decode('utf-8')))
        except pymysql.err.IntegrityError:
            return render_template("signup.html", error="Benutzername existiert bereits. Bitte wählen Sie einen anderen.")
        except Exception as e:
             print(f"Database error during signup: {e}")
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
        
        if not username or not password:
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
            print(f"Database error during signin: {e}")
            return render_template("error_500.html", error_message="Fehler beim Anmeldevorgang."), 500

        # Prüfen, ob Benutzer existiert und Passwort übereinstimmt
        if user and bcrypt.checkpw(password.encode('utf-8'), user["password_hash"].encode('utf-8')):
            session["user"] = username
            return redirect(url_for('dashboard'))
        else:
            return render_template("signin.html", error="Ungültige Anmeldedaten.")

    return render_template("signin.html")

@app.route("/dashboard")
@check_db_availability
@login_required
def dashboard():
    return render_template("dashboard.html", user=session["user"])

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for('index'))

# --- FEHLER-HANDLER ---

@app.errorhandler(503)
def service_unavailable_error(e):
    return render_template("error_init.html"), 503

@app.errorhandler(404)
def page_not_found(e):
    return render_template("error_404.html"), 404

@app.errorhandler(500)
def internal_server_error(e):
    # Zeigt eine generische Meldung an, da die Fehlerursache intern ist
    return render_template("error_500.html", error_message="Ein interner Serverfehler ist aufgetreten."), 500


if __name__ == "__main__":
    # In einem Gunicorn/Worker-Setup wird dieser Block nicht ausgeführt. 
    # Die Initialisierung sollte über das externe Skript erfolgen, das init_db() aufruft.
    pass