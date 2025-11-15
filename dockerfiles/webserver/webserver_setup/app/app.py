from flask import Flask, request, render_template, redirect, url_for, session, flash
from werkzeug.security import generate_password_hash, check_password_hash
import pymysql
import os
import re

app = Flask(__name__, template_folder='templates')

# Database config from environment variables
DB_HOST = os.environ.get('DB_HOST', '10.10.40.2')
DB_PORT = int(os.environ.get('DB_PORT', 3306))
DB_USER = os.environ.get('DB_USER', '')
DB_PASS = os.environ.get('DB_PASS', '')
DB_NAME = os.environ.get('DB_NAME', '')

# Flask secret key
app.secret_key = os.environ.get('FLASK_SECRET', '')

USERNAME_RE = re.compile(r'^[A-Za-z0-9_.-]{3,64}$')
MIN_PASSWORD_LEN = 8

def get_db_conn():
    return pymysql.connect(host=DB_HOST, port=DB_PORT, user=DB_USER,
                           password=DB_PASS, charset='utf8mb4',
                           cursorclass=pymysql.cursors.DictCursor,
                           autocommit=True)

def init_db():
    """Create database and tables if they do not exist"""
    conn = get_db_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS {DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
            cur.execute(f"USE {DB_NAME}")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    username VARCHAR(64) NOT NULL UNIQUE,
                    password_hash VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                ) ENGINE=InnoDB
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS entries (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    user_id INT NOT NULL,
                    content TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB
            """)
    finally:
        conn.close()

# Initialize DB on startup
init_db()

# ---------------- Flask Routes ---------------- #

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/auth')
def auth_choice():
    return render_template('auth_choice.html')

@app.route('/signup', methods=['GET','POST'])
def signup():
    if request.method == 'POST':
        username = request.form.get('username','').strip()
        password = request.form.get('password','')

        if not USERNAME_RE.match(username):
            flash('Username invalid (3-64 letters/numbers/._-)')
            return redirect(url_for('signup'))
        if len(password) < MIN_PASSWORD_LEN:
            flash(f'Password must be at least {MIN_PASSWORD_LEN} characters')
            return redirect(url_for('signup'))

        password_hash = generate_password_hash(password, method='pbkdf2:sha256', salt_length=16)
        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute(f"USE {DB_NAME}")
                cur.execute("INSERT INTO users (username, password_hash) VALUES (%s,%s)", (username, password_hash))
            flash('Signup successful. Please sign in.')
            return redirect(url_for('auth_choice'))
        except pymysql.err.IntegrityError:
            flash('Username already exists')
            return redirect(url_for('signup'))
        finally:
            try: conn.close()
            except: pass

    return render_template('signup.html')

@app.route('/signin', methods=['GET','POST'])
def signin():
    if request.method == 'POST':
        username = request.form.get('username','').strip()
        password = request.form.get('password','')
        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute(f"USE {DB_NAME}")
                cur.execute("SELECT id, password_hash FROM users WHERE username=%s", (username,))
                row = cur.fetchone()
            if not row or not check_password_hash(row['password_hash'], password):
                flash('Credentials wrong')
                return redirect(url_for('signin'))
            session['user_id'] = row['id']
            session['username'] = username
            return redirect(url_for('dashboard'))
        finally:
            try: conn.close()
            except: pass
    return render_template('signin.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('index'))

@app.route('/dashboard', methods=['GET','POST'])
def dashboard():
    if 'user_id' not in session:
        return redirect(url_for('signin'))

    user_id = session['user_id']

    if request.method == 'POST':
        content = request.form.get('content','').strip()
        if not content:
            flash('Content cannot be empty')
            return redirect(url_for('dashboard'))
        try:
            conn = get_db_conn()
            with conn.cursor() as cur:
                cur.execute(f"USE {DB_NAME}")
                cur.execute("INSERT INTO entries (user_id, content) VALUES (%s,%s)", (user_id, content))
        finally:
            try: conn.close()
            except: pass
        return redirect(url_for('dashboard'))

    # fetch entries
    try:
        conn = get_db_conn()
        with conn.cursor() as cur:
            cur.execute(f"USE {DB_NAME}")
            cur.execute("""
                SELECT e.id, e.content, e.created_at, u.username
                FROM entries e JOIN users u ON u.id = e.user_id
                ORDER BY e.created_at DESC
            """)
            rows = cur.fetchall()
    finally:
        try: conn.close()
        except: rows = []

    return render_template('dashboard.html', entries=rows, username=session.get('username'))

@app.route('/health')
def health():
    return 'ok', 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
