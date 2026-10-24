const BACKEND_HOST = process.env.BACKEND_HOST || '127.0.0.1';
const BACKEND_PORT = process.env.BACKEND_PORT || '8000';

async function getMessages() {
  const res = await fetch(`http://${BACKEND_HOST}:${BACKEND_PORT}/api/messages`, {
    cache: 'no-store',
  });
  if (!res.ok) return [];
  return res.json();
}

export default async function Home() {
  const messages = await getMessages();

  return (
    <main style={{ fontFamily: 'sans-serif', padding: 40 }}>
      <h1>Демо: Next.js + FastAPI + PostgreSQL</h1>
      <p>Данные получены с backend, который читает их из Postgres.</p>
      <ul>
        {messages.map((m) => (
          <li key={m.id}>
            <b>#{m.id}</b> — {m.text}{' '}
            <small>({new Date(m.created_at).toLocaleString()})</small>
          </li>
        ))}
      </ul>
    </main>
  );
}