import psycopg2
import bcrypt

conn = psycopg2.connect(
    dbname="4dev", user="chan", password="1234", host="localhost", port="6546"
)
cur = conn.cursor()

def create_user(username, email, password):
    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    cur.execute("INSERT INTO user_info (username, email, password_hash) VALUES (%s, %s, %s)",
                (username, email, password_hash))
    conn.commit()

def validate_user(email, password):
    cur.execute("SELECT password_hash FROM user_info WHERE email = %s", (email,))
    result = cur.fetchone()
    if result:
        return bcrypt.checkpw(password.encode(), result[0].encode())
    return False
