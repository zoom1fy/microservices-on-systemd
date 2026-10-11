CREATE DATABASE demo;
CREATE USER demo WITH PASSWORD 'demo';
GRANT ALL PRIVILEGES ON DATABASE demo TO demo;
\c demo
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO messages (text) VALUES ('Привет из PostgreSQL!'), ('Второе сообщение');
GRANT ALL ON messages TO demo;
GRANT USAGE, SELECT ON SEQUENCE messages_id_seq TO demo;