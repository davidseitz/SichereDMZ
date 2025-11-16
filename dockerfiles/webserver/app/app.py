from flask import Flask, render_template, request, redirect, session
import pymysql
import bcrypt
import os

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET", "devsecret")

DB_HOST = os.getenv("DB_HOST", "10.10.40.2")
DB_PORT = int(os.getenv("DB_PORT", 3306))
DB_USER = os.getenv("DB_USER", "webuser")
DB_PASS = os.getenv("DB_PASS", "webpass")
DB_NAME = os.getenv("DB_NAME", "webapp")

def get_db_conn():
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


@app.route("/")
def index():
    return render_template("index.html")

@app.route("/auth")
def auth_choice():
    return render_template("auth_choice.html")

@app.route("/signup", methods=["GET", "POST"])
def signup():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        if not username or not password:
            return render_template("signup.html", error="All fields required.")

        pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt())

        try:
            conn = get_db()
            with conn.cursor() as cur:
                cur.execute("INSERT INTO users (username, password) VALUES (%s, %s)", 
                            (username, pw_hash))
                conn.commit()
        except Exception:
            return render_template("signup.html", error="Username already exists.")
        finally:
            conn.close()

        return redirect("/signin")

    return render_template("signup.html")

@app.route("/signin", methods=["GET", "POST"])
def signin():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE username=%s", (username,))
            user = cur.fetchone()
        conn.close()

        if user and bcrypt.checkpw(password.encode(), user["password"].encode()):
            session["user"] = username
            return redirect("/dashboard")
        else:
            return render_template("signin.html", error="Invalid credentials.")

    return render_template("signin.html")

@app.route("/dashboard")
def dashboard():
    if "user" not in session:
        return redirect("/signin")
    return render_template("dashboard.html", user=session["user"])

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/")

@app.errorhandler(500)
def error_page(e):
    return render_template("error.html"), 500

if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
