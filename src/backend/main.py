import os
from fastapi import FastAPI
import psycopg

app = FastAPI()

DB_DSN = os.getenv(
    "DB_DSN",
    "postgresql://demo:demo@localhost:5432/demo"
)

@app.get("/api/health")
def health():
    return {"status": "ok"}

@app.get("/api/messages")
def get_messages():
    with psycopg.connect(DB_DSN) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, text, created_at FROM messages ORDER BY id")
            rows = cur.fetchall()
    return [
        {"id": r[0], "text": r[1], "created_at": r[2].isoformat()}
        for r in rows
    ]