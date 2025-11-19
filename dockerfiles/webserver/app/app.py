from flask import Flask, render_template, request, redirect, session
import pymysql
import bcrypt
import os
from functools import wraps # Import for the decorator

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET", "devsecret")

DB_HOST = os.getenv("DB_HOST", "10.10.40.2")
DB_PORT = int(os.getenv("DB_PORT", 3306))
DB_USER = os.getenv("DB_USER", "webuser")
DB_PASS = os.getenv("DB_PASS", "webpass")
DB_NAME = os.getenv("DB_NAME", "webapp")

# --- GLOBAL DATABASE STATE FLAG ---
DB_AVAILABLE = False 

def get_db_conn():
    """Attempts to return a database connection, raising OperationalError on failure."""
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
    """Initializes the database schema and sets the global DB_AVAILABLE flag."""
    global DB_AVAILABLE
    retry = 10
    while retry > 0:
        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                # Create users table
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS users (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        username VARCHAR(50) UNIQUE NOT NULL,
                        password_hash VARCHAR(255) NOT NULL
                    )
                """)
            conn.close()
            DB_AVAILABLE = True
            print("Database initialized and connection confirmed.")
            break
        except pymysql.err.OperationalError as e:
            retry -= 1
            print(f"Database connection failed during init. Retry {retry}")
    if DB_AVAILABLE != True:
        print("Couln't establish connection!")
    
    

# --- DECORATOR TO CHECK DATABASE AVAILABILITY ---
def check_db_availability(f):
    """If the DB is not available, render error.html with 503 status."""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not DB_AVAILABLE:
            # Service Unavailable (503) is the correct code for dependency failure
            return render_template("error.html"), 503 
        return f(*args, **kwargs)
    return decorated_function

# --- ROUTE HANDLERS ---

@app.route("/")
@check_db_availability
def index():
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
            return render_template("signup.html", error="All fields required.")

        pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
        conn = None # Initialize conn

        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                # IMPORTANT: Corrected 'password' to 'password_hash' to match table schema
                cur.execute("INSERT INTO users (username, password_hash) VALUES (%s, %s)", 
                            (username, pw_hash))
                # commit is usually done automatically with autocommit=True, but harmless here
                conn.commit() 
        except pymysql.err.IntegrityError:
            # Handle unique constraint violation (username already exists)
            return render_template("signup.html", error="Username already exists.")
        except Exception:
            # Catch any other database error during insert
             return render_template("error.html"), 500
        finally:
            if conn:
                conn.close()

        return redirect("/signin")

    return render_template("signup.html")

@app.route("/signin", methods=["GET", "POST"])
@check_db_availability
def signin():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        
        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute("SELECT password_hash FROM users WHERE username=%s", (username,))
                user = cur.fetchone()
            conn.close()
        except Exception:
            # Catch any other database error during insert
             return render_template("error.html"), 500

        # IMPORTANT: Corrected user['password'] to user['password_hash']
        if user and bcrypt.checkpw(password.encode(), user["password_hash"].encode()):
            session["user"] = username
            return redirect("/dashboard")
        else:
            return render_template("signin.html", error="Invalid credentials.")

    return render_template("signin.html")

@app.route("/dashboard")
def dashboard():
    # Since dashboard usually relies on user session, we can skip the DB check 
    # unless the dashboard itself performs a DB query. Let's add the check anyway
    # for consistency, though session access doesn't require the DB.
    if not DB_AVAILABLE:
        return render_template("error.html"), 503
        
    if "user" not in session:
        return redirect("/signin")
        
    return render_template("dashboard.html", user=session["user"])

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/")

# --- ERROR HANDLERS ---

# Use 503 (Service Unavailable) for database failure, not 502 (Bad Gateway)
@app.errorhandler(503)
@app.errorhandler(502) # Keep 502 just in case, but 503 is correct for dependency failure
def service_unavailable_error(e):
    return render_template("error.html"), e.code if hasattr(e, 'code') else 503


if __name__ == "__main__":
    # 1. Attempt to initialize the database (this sets the DB_AVAILABLE flag)
    init_db()
    
    # 2. Start the application
    app.run(host="0.0.0.0", port=80)