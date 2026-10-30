# Оглавление
[[#Глава 1. Теоретические основы]]
- [[#1. Историческая справка]]
- [[#2. Архитектура и компоненты]]
- [[#3. Юниты]]

[[#Глава 2. Микросервисы]]
- [[#1. Что такое микросервисы?]]
- [[#2. systemd как альтернатива Docker]]

[[#Глава 3. Практика]]
- [[#1. Пишем демо-проект]]
- [[#2. Вспомогательные скрипты]]
- [[#3. Написание юнитов]]

[[#Глава 4. Как всем этим управлять]]
- [[#1. Логи и диагностика]]
- [[#2. Обновление приложения]]
- [[#3. Откат на предыдущую версию]]

[[#Глава 5. Сравнение производительности]]

[[#Глава 6. Вывод]]

---
# Глава 1. Теоретические основы

#### 1. Историческая справка

До появления `systemd` в большинстве дистрибутивов Linux использовалась классическая система инициализации **SysVinit**, созданная ещё на заре Unix.

Основной проблемой `SysVinit` было то, что каждый процесс или сервис запускался строго один за другим. Если один скрипт зависал, то загрузка всей операционной системы останавливалась. Сами сценарии запуска представляли собой громоздкие и сложные Bash-скрипты.

В 2010 году инженеры Леннарт Поттеринг (Lennart Poettering) и Кей Сиверс (Kay Sievers) из компании *Red Hat* представили проект `systemd`. Они предложили принципиально новый подход:
* **Параллелизм**: запуск сервисов происходит одновременно, без ожидания готовности предыдущих.
* **Использование сокетов**: система создает точки подключения (sockets) для всех служб сразу. Если один сервис хочет отправить данные другому, который ещё не загрузился, данные буферизируются, а принимающий сервис стартует автоматически.
* **Декларативный подход**: вместо сложных Bash-скриптов управление перешло на простые конфигурационные файлы (юниты).

В начале 2010-х годов началась **«Великая война систем инициализации»**. Философия Unix гласит: «Программа должна делать что-то одно и делать это хорошо». Старый `SysVinit` делал только одно — запускал процессы, а `systemd` быстро превратился из простой системы инициализации в огромного «монстра». Сегодня он также управляет сетевыми подключениями, системным временем, учётными записями пользователей и ещё много чем. Сторонники `SysVinit` посчитали, что `systemd` забирает под себя всю операционную систему, превращаясь в неделимый монолит. Также `systemd` внедрил свой компонент `journald`, который записывает логи в бинарном (двоичном) формате. Пользователь больше не может просто открыть файл лога текстовым редактором. Чтобы прочитать его, он обязан использовать специальную утилиту `journalctl`. Старожилы сочли это предательством текстовой философии Linux и указали на риск: при повреждении бинарного журнала восстановление может быть затруднено, хотя `journald` предусматривает резервирование данных и проверку через `journalctl --verify`. Но при всём при этом `systemd` быстро доказал свою эффективность. Уже к **2015 году** он стал стандартом де-факто и был принят по умолчанию в большинстве крупнейших дистрибутивов: *Debian, Ubuntu, Fedora, Red Hat Enterprise Linux (RHEL), CentOS и Arch Linux*.

Финальный аккорд произошёл в марте 2026 года с релизом systemd 260, в котором разработчики удалили поддержку SysV/LSB init-скриптов: `systemd-sysv-generator`, `systemd-sysv-install` и `rc-local.service`. `systemd` — победил.

#### 2. Архитектура и компоненты

Проект `systemd` — это не один монолитный процесс, а модульный комплекс, состоящий из множества специализированных демонов (компонентов) и утилит управления. Каждый компонент отвечает за свою строгую задачу. Схематично архитектуру можно разделить на три уровня: ядро (PID 1), системные демоны и утилиты управления.

**systemd (PID 1)** — главное «сердце» подсистемы. Он запускается сразу после ядра Linux, управляет очередью загрузки, обрабатывает зависимости между сервисами, слушает сокеты и координирует работу всех остальных модулей.

Каждая подсистема автоматизирует конкретную задачу:
*   **journald** — локальный сборщик системных логов. Он перехватывает сообщения от ядра, сервисов и собирает их в единый защищённый бинарный журнал.
*   **logind** — менеджер пользовательских сессий, рабочих столов и управления питанием.
*   **networkd** — демон для настройки сетевых интерфейсов и управления сетевыми подключениями.
*   **resolved** — сетевой DNS-резолвер, который кэширует запросы и управляет конфигурацией DNS-серверов.
*   **timesyncd** — легковесный компонент для синхронизации системного времени по протоколу NTP.

Для взаимодействия со всеми этими демонами используются консольные команды:
*   `systemctl` — главный инструмент для администратора. Используется для управления юнитами: запуска, остановки, перезапуска, включения в автозагрузку и проверки статуса сервисов.
*   `journalctl` — утилита для чтения, фильтрации и анализа бинарных логов, собранных демоном `journald`.
*   `loginctl` — команда для просмотра активных сессий пользователей и управления ими.
*   `timedatectl` — инструмент для настройки часового пояса, даты и системного времени.
*   `hostnamectl` — утилита для изменения сетевого имени компьютера (hostname) и просмотра информации об ОС.

#### 3. Юниты

**Юнит (Unit)** — конфигурационный файл, из которого строится вся система управления в `systemd`.
##### Основные типы юнитов

В `systemd` существует 11 типов юнитов, но для развёртывания микросервисов и администрирования чаще всего используются следующие пять:
*   **.service (Сервисы)** — самый частый тип юнитов. Описывает службы, которые должны работать постоянно или выполнять фоновые задачи (например, ваш веб-сервер, Go/Python-микросервис, база данных).
*   **.socket (Сокеты)** — инкапсулирует сетевой порт или IPC-сокет в файловой системе. Используется для той самой «активации по сокету», позволяя отложить запуск тяжелого `.service`-юнита до тех пор, пока к нему кто-то не обратится.
*   **.target (Цели)** — логическая группировка других юнитов. Например, `multi-user.target` объединяет все службы, необходимые для работы системы в многопользовательском режиме без графики, а `graphical.target` — с графическим интерфейсом.
*   **.timer (Таймеры)** — аналог планировщика задач `cron`. Позволяет запускать определенные `.service`-юниты по расписанию (например, раз в час или каждую среду в 3:00) или через заданный промежуток времени после загрузки системы.
*   **.path (Пути)** — юнит, который следит за файлом или директорией. Как только файл изменяется, удаляется или появляется, `.path` автоматически активирует связанный с ним сервис (удобно для автоматической обработки загруженных картинок или логов).

##### Где хранятся юнит-файлы?

В системе есть три основные директории для конфигурации юнитов, и у них строгий приоритет:
1.  `/lib/systemd/system/` (или `/usr/lib/...`) — системные юниты, которые устанавливаются менеджером пакетов. Изменять файлы здесь нельзя, так как при обновлении программы они перезапишутся.
2.  `/etc/systemd/system/` — главное место для администратора. Сюда вы кладете свои собственные юниты. Также сюда записываются изменения, если вы переопределяете системные службы. Юниты из этой папки имеют наивысший приоритет и перекрывают файлы из `/lib/`.
3.  `/run/systemd/system/` — динамические юниты, создаваемые программами во время работы системы. Они исчезают после перезагрузки.

---
# Глава 2. Микросервисы

#### 1. Что такое микросервисы?

В современной разработке доминируют два подхода к архитектуре приложений: монолитный и микросервисный. Микросервисная архитектура — это подход, при котором крупное приложение разбивается на наборы мелких, независимых друг от друга сервисов (программ).

Каждый такой микросервис:
*   Решает только одну конкретную бизнес-задачу (например: один сервис отвечает за авторизацию пользователей, второй — за отправку SMS, третий — за обработку платежей).
*   Работает как отдельный процесс в операционной системе.
*   Общается с другими сервисами по сети через легкие протоколы (HTTP/REST, gRPC, брокеры сообщений вроде RabbitMQ).
*   Может быть написан на любом языке программирования (например, сервис авторизации на Go, а сервис аналитики на Python) и использовать свою собственную базу данных.

##### Сравнение: Монолит vs Микросервисы

| Критерий               | Монолит                                                                                        | Микросервисы                                                                                               |
| :--------------------- | :--------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------- |
| **Структура**          | Всё приложение — это один огромный код и один процесс.                                         | Приложение разделено на десятки автономных процессов.                                                      |
| **Отказоустойчивость** | Если падает одна функция, падает всё приложение целиком.                                       | Если падает один сервис (например, отправка SMS), остальные функции (каталог, оплата) продолжают работать. |
| **Масштабирование**    | Приходится копировать весь монолит целиком, даже если нагрузка выросла только на одну функцию. | Можно изолированно масштабировать (выделять больше ресурсов) только тот сервис, который перегружен.        |
| **Обновление**         | Чтобы обновить одну строчку кода, нужно заново компилировать и перезапускать всё приложение.   | Каждый сервис можно обновлять и перезапускать независимо, не прерывая работу всей системы.                 |

#### 2. systemd как альтернатива Docker

В современной индустрии стандартом для развёртывания микросервисов принято считать контейнеризацию (Docker) и оркестрацию (Kubernetes). Однако в рамках проектирования архитектуры систем важно избегать избыточности и выбирать инструмент под конкретные задачи. `systemd` является мощным, нативным и легковесным решением для запуска микросервисов непосредственно на хост-системе Linux.

##### Почему systemd — это полноценный инструмент для микросервисов?
1.  **Управление жизненным циклом и зависимостями:** `systemd` позволяет выстроить строгую очередность запуска.
2. **Оркестрация на минималках (Самовосстановление и динамические ресурсы):** `systemd` мгновенно перезапускает микросервис при аварийном падении, а также позволяет без остановки процесса динамически выделять или ограничивать ресурсы.
3. **Использование cgroups для лимитов:** `systemd` под капотом использует тот же механизм ядра Linux для ограничения ресурсов, что и Docker — **cgroups**. Мы можем прямо в юните прописать `MemoryMax=512M` и `CPUQuota=20%`, полностью защитив сервер от зависания из-за одного прожорливого микросервиса.
4.  **Безопасность и изоляция:** `systemd` даёт значительный уровень изоляции, достаточный для многих сценариев, но не заменяет полноценную контейнерную изоляцию. Можно в значительной степени ограничить доступ микросервиса к чужим файлам и системным директориям, даже если его взломают.
5.  **Нативный сбор метрик и логов:** Все микросервисы пишут логи в стандартный поток (stdout), а `systemd` через `journald` автоматически собирает их и структурирует по времени, позволяя обходиться без тяжёлых систем вроде ELK-стека для локальных логов. Для сбора логов с нескольких хостов нужен отдельный механизм, например `systemd-journal-remote`.

**Вывод для проекта:** Использование `systemd` для микросервисов — это осознанный архитектурный выбор в пользу максимальной производительности, экономии ресурсов сервера и снижения сложности инфраструктуры, когда полная изоляция файловой системы (как в Docker) не является критически необходимой.

---
# Глава 3. Практика

Для запуска понадобятся Debian или Ubuntu с `systemd`, доступ к root, Node.js 18.17+, npm, Python 3 с `venv` и PostgreSQL. `install.sh` ставит зависимости через `apt`, поэтому на других дистрибутивах пакеты нужно установить вручную.

Перед установкой скопируйте шаблон конфигурации:

```bash
cp .env.example .env
```

Дерево проекта:
```
.
├── .env.example                 # шаблон конфигурации
├── build.sh                     # сборка версионированных артефактов
├── install.sh                   # установка и первый запуск
├── uninstall.sh                 # удаление systemd-юнитов
├── db/
│   ├── init.sql                 # создание БД, пользователя и таблицы
│   └── init-once.sh             # идемпотентная инициализация БД
├── scripts/
│   ├── install-deps.sh          # установка зависимостей через apt
│   └── install-systemd-units.sh # рендеринг и установка юнитов
├── src/
│   ├── backend/                 # FastAPI-приложение и requirements.txt
│   └── frontend/                # Next.js-приложение
└── systemd/
    ├── demo-app.target
    ├── demo-app.backend.service
    ├── demo-app.frontend.service
    └── demo-app.db-init.service
```

#### 1. Пишем демо-проект

Для демонстрации возможностей `systemd` как альтернативы `Docker` нам нужен демонстрационный проект. Предлагаю взять стандартную трёхуровневую архитектуру: клиент, сервер, база данных. Стек технологий следующий: Next.js, FastAPI, PostgreSQL. Не будем разрабатывать суперсложное приложение, достаточно базовой демонстрации. Клиент запросит с сервера сообщения, сервер прочитает их из базы данных и вернёт. Проще некуда.

##### .env.example

Будем делать правильно и вынесем нужные данные в файл с переменными окружения. Шаблон лежит в `.env.example`, рабочая копия — `.env`:

`.env.example`
```env
DB_DSN=postgresql://demo:demo@localhost:5432/demo

BACKEND_HOST=127.0.0.1
BACKEND_PORT=8000

FRONTEND_HOST=0.0.0.0
FRONTEND_PORT=3000
```

##### Клиент (Next.js)

*src/frontend/package.json*
```json
{
  "name": "demo-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start"
  },
  "dependencies": {
    "next": "14.2.15",
    "react": "18.3.1",
    "react-dom": "18.3.1"
  }
}
```

*src/frontend/next.config.js*
```js
const BACKEND_HOST = process.env.BACKEND_HOST || '127.0.0.1';
const BACKEND_PORT = process.env.BACKEND_PORT || '8000';

const nextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `http://${BACKEND_HOST}:${BACKEND_PORT}/api/:path*`,
      },
    ];
  },
};
module.exports = nextConfig;
```

*src/frontend/app/page.js*
```js
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
```

*src/frontend/app/layout.js*
```js
export const metadata = { title: 'Demo Microservices' };

export default function RootLayout({ children }) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
```

##### Сервер (FastAPI)

requirements.txt
```txt
fastapi==0.115.0
uvicorn[standard]==0.32.0
psycopg[binary]==3.2.3
```

main.py
```py
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
```

##### База данных

Для базы данных написан вот такой `db/init.sql` с добавлением одной таблички:
```sql
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
```

#### 2. Вспомогательные скрипты

Для минимальной автоматизации нам понадобятся скрипты для установки, удаления, сборки и инициализации базы данных.

##### Развёртывание сервисов

`install.sh` выполняет следующие шаги:
1. Определяет корень проекта `ROOT`.
2. Устанавливает системные зависимости через `apt`.
3. Создаёт системного пользователя и группу `demo`.
4. Выставляет права на `.env` (файл должен уже существовать).
5. Разрешает пользователям `demo` и `postgres` проход по родительским каталогам проекта. Если `setfacl` недоступен, используется `chmod o+x`.
6. Включает и запускает `postgresql.service`.
7. Добавляет в `/etc/postgresql/*/main/pg_hba.conf` локальную peer-аутентификацию для пользователя `postgres`.
8. Отключает `demo-app.db-init.service`, если он был включён, и рендерит systemd-юниты из `systemd/` в `/etc/systemd/system/`.
9. Останавливает ранее запущенные backend и frontend.
10. Собирает артефакты, если `artifacts/current` ещё не существует.
11. Сбрасывает состояние `failed` и запускает `demo-app.db-init.service`.
12. Включает и запускает `demo-app.target`.

`scripts/install-deps.sh` — тонкая обёртка над `apt-get`; она ставит `nodejs`, `npm`, `python3`, `python3-venv`, `postgresql` и `postgresql-client`.

Пункт 5 стоит держать в голове: при отсутствии `setfacl` скрипт добавляет другим пользователям право прохода по родительским каталогам. На системах с ACL доступ выдаётся точечно.

Повторный `install.sh` не пересобирает уже существующие артефакты. Для обновления кода используйте `build.sh`.

```bash
#!/bin/bash
set -euo pipefail

ROOT="${INSTALL_ROOT:-$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)}"

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

echo "==> installing system dependencies"
"$ROOT/scripts/install-deps.sh" nodejs npm python3 python3-venv postgresql postgresql-client

echo "==> creating demo system user/group (if missing)"
if ! getent group demo >/dev/null 2>&1; then
    groupadd --system demo
fi
if ! id demo >/dev/null 2>&1; then
    useradd --system --gid demo --home-dir /home/demo --shell /usr/sbin/nologin demo
fi
install -d -o demo -g demo /home/demo
chmod 600 "$ROOT/.env"

echo "==> granting service accounts access to $ROOT"
grant_traverse() {
    local dir=$1 mode
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if command -v setfacl >/dev/null 2>&1 && \
           setfacl -m u:demo:x -m u:postgres:x "$dir" 2>/dev/null; then
            :
        else
            mode=$(stat -c '%a' "$dir" 2>/dev/null || echo "")
            case "$mode" in
                *[13579]|"") ;;
                *) chmod o+x "$dir" 2>/dev/null || true ;;
            esac
        fi
        dir=$(dirname -- "$dir")
    done
}
grant_traverse "$(dirname -- "$ROOT")"

echo "==> starting PostgreSQL"
systemctl enable --now postgresql.service

echo "==> allowing local 'postgres' peer authentication"
hba="$(ls /etc/postgresql/*/main/pg_hba.conf 2>/dev/null | head -n1 || true)"
if [ -n "$hba" ] && \
   ! grep -qE '^[[:space:]]*local[[:space:]]+all[[:space:]]+postgres[[:space:]]+(peer|trust)' "$hba"; then
    tmp="$(mktemp)"
    { echo "local   all   postgres   peer"; cat "$hba"; } > "$tmp"
    cat "$tmp" > "$hba"
    rm -f "$tmp"
    systemctl reload postgresql.service
fi

echo "==> deploying systemd units"
systemctl disable "demo-app.db-init.service" 2>/dev/null || true

"$ROOT/scripts/install-systemd-units.sh"

echo "==> stopping previously running services"
systemctl stop demo-app.frontend.service demo-app.backend.service 2>/dev/null || true

echo "==> building artifacts (if missing)"
if [ ! -e "$ROOT/artifacts/current" ]; then
    "$ROOT/build.sh"
else
    echo "artifacts/current exists; run $ROOT/build.sh to refresh"
fi

echo "==> initializing demo database (dev helper)"
systemctl reset-failed demo-app.db-init.service 2>/dev/null || true
systemctl start demo-app.db-init.service

echo "==> enabling and starting demo-app.target"
systemctl enable --now demo-app.target

echo
echo "=== status ==="
systemctl status demo-app.target --no-pager -n 3 || true
```

##### Установка systemd-юнитов

Скрипт `scripts/install-systemd-units.sh` копирует шаблоны из `systemd/` в `/etc/systemd/system/` и заменяет плейсхолдеры `@ROOT@`, `@NODE@` и `@PROTECTHOME@`:

- `@ROOT@` — абсолютный путь к проекту;
- `@NODE@` — путь к исполняемому файлу `node`;
- `@PROTECTHOME@` — `read-only`, если проект лежит в `/home/*` или `/root/*`, иначе `yes`.

Последний пункт важен: при `ProtectHome=yes` каталог `/home` становится недоступен сервису, поэтому для проекта в домашнем каталоге используется `read-only`.

*scripts/install-systemd-units.sh*
```bash
#!/bin/bash
set -euo pipefail

ROOT="${INSTALL_ROOT:-$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)}"

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

NODE="$(command -v node || echo /usr/bin/node)"

case "$ROOT" in
    /home/*|/root/*) PROTECT_HOME=read-only ;;
    *)               PROTECT_HOME=yes ;;
esac

for tmpl in "$ROOT"/systemd/*.service "$ROOT"/systemd/*.target; do
    unit="/etc/systemd/system/$(basename -- "$tmpl")"
    : > "$unit"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//@ROOT@/$ROOT}"
        line="${line//@PROTECTHOME@/$PROTECT_HOME}"
        printf '%s\n' "${line//@NODE@/$NODE}" >> "$unit"
    done < "$tmpl"
    chmod 0644 "$unit"
    echo "installed $unit"
done

systemctl daemon-reload
```

##### Сборка и артефакты

`build.sh` создаёт отдельную версию приложения в `artifacts/<REV>`:

```
artifacts/
├── 20261023121837/
│   ├── backend/
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── .venv/
│   └── frontend/
│       ├── .next/
│       ├── app/
│       ├── node_modules/
│       ├── next.config.js
│       └── package.json
├── 20261023123434/
└── current -> 20261023123434
```

- `REV` по умолчанию — UTC-время сборки. Можно задать вручную: `sudo REV=v1 ./build.sh`.
- Backend собирается в отдельное виртуальное окружение `.venv`.
- Если в системе нет `ensurepip`, скрипт создаёт venv без pip и устанавливает pip через `get-pip.py`.
- Frontend собирается командой `npm ci && npm run build`.
- Симлинк `artifacts/current` указывает на актуальную версию.

Сервисы работают с путём `artifacts/current`, поэтому переключение версии выполняется заменой симлинка.

*build.sh*
```bash
#!/bin/bash
set -euo pipefail

ROOT="${INSTALL_ROOT:-$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)}"

if [ -f "$ROOT/.env" ]; then
    set -a
    . "$ROOT/.env"
    set +a
fi

SRC="$ROOT/src"
ART="$ROOT/artifacts"
REV="${REV:-$(date -u +%Y%m%d%H%M%S)}"
DEST="$ART/$REV"

for bin in python3 npm; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "missing '$bin'; run as root: sudo $ROOT/install.sh" >&2
        exit 1
    }
done

mkdir -p "$ART"

if [ -e "$DEST" ]; then
    echo "artifact '$REV' already exists; set REV=<new-id> or remove $DEST" >&2
    exit 1
fi

echo "==> building backend ($REV)"
mkdir -p "$DEST/backend"
cp "$SRC/backend/main.py" "$SRC/backend/requirements.txt" "$DEST/backend/"

if python3 -c "import ensurepip" >/dev/null 2>&1; then
    python3 -m venv "$DEST/backend/.venv"
else
    echo "ensurepip missing, creating venv without pip and bootstrapping it"
    python3 -m venv --without-pip "$DEST/backend/.venv"
    if command -v wget >/dev/null 2>&1; then
        wget -qO "$DEST/get-pip.py" https://bootstrap.pypa.io/get-pip.py
        "$DEST/backend/.venv/bin/python" "$DEST/get-pip.py"
        rm -f "$DEST/get-pip.py"
    elif command -v curl >/dev/null 2>&1; then
        curl -sS -L https://bootstrap.pypa.io/get-pip.py -o "$DEST/get-pip.py"
        "$DEST/backend/.venv/bin/python" "$DEST/get-pip.py"
        rm -f "$DEST/get-pip.py"
    else
        echo "need curl or wget to bootstrap pip" >&2
        exit 1
    fi
fi

"$DEST/backend/.venv/bin/pip" install --upgrade pip
"$DEST/backend/.venv/bin/pip" install -r "$DEST/backend/requirements.txt"

echo "==> building frontend ($REV)"
mkdir -p "$DEST/frontend"
cp "$SRC/frontend/package.json" "$SRC/frontend/package-lock.json" \
   "$SRC/frontend/next.config.js" "$DEST/frontend/"
cp -r "$SRC/frontend/app" "$DEST/frontend/app"
(
    cd "$DEST/frontend"
    npm ci
    npm run build
)

chmod -R a+rX "$DEST"

ln -sfn "$REV" "$ART/current"
echo "==> done: $DEST (current -> $REV)"
```

##### Инициализация базы данных

Автоматически ждём, пока база данных поднимется, проверяем, существует ли БД `demo`, и если её нет — накатывает начальный SQL-скрипт.

*db/init-once.sh*
```bash
#!/bin/bash
set -eu

ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)"

for _ in $(seq 1 30); do
    pg_isready -q && break
    sleep 1
done
if ! pg_isready -q; then
    echo "postgresql is not ready" >&2
    exit 1
fi

if [ "$(psql -tAc "SELECT 1 FROM pg_database WHERE datname='demo'")" != "1" ]; then
    psql -v ON_ERROR_STOP=1 -f "$ROOT/db/init.sql"
    echo "database demo initialized"
else
    echo "database demo already exists, skipping"
fi
```

##### Удаление

Скрипт `uninstall.sh` останавливает и отключает сервисы, удаляет юниты из `/etc/systemd/system/`, выполняет `daemon-reload`. Не удаляются: собранные артефакты в `artifacts/`, `.env`, пользователь `demo`, база данных и данные PostgreSQL.

```bash
#!/bin/bash
set -euo pipefail

ROOT="${INSTALL_ROOT:-$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)}"

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

echo "==> stopping and disabling demo-app"
systemctl disable --now demo-app.target 2>/dev/null || true
systemctl disable demo-app.frontend.service demo-app.backend.service \
                   demo-app.db-init.service 2>/dev/null || true
systemctl stop demo-app.frontend.service demo-app.backend.service \
               demo-app.db-init.service 2>/dev/null || true

echo "==> removing systemd units"
rm -f /etc/systemd/system/demo-app.target \
      /etc/systemd/system/demo-app.backend.service \
      /etc/systemd/system/demo-app.frontend.service \
      /etc/systemd/system/demo-app.db-init.service

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo "done; built artifacts left in $ROOT/artifacts"
```

Полная очистка выполняется вручную и требует осторожности:

```shell
sudo userdel -r demo
sudo -u postgres dropdb demo
sudo -u postgres dropuser demo
sudo rm -rf artifacts
```

#### 3. Написание юнитов

Наконец-то переходим к написанию юнитов. Их будет четыре: клиент, сервер, инициализатор БД и общий target. PostgreSQL при этом остаётся отдельным системным сервисом.

В листингах ниже есть плейсхолдеры `@ROOT@`, `@NODE@` и `@PROTECTHOME@`. Их подставляет `scripts/install-systemd-units.sh` при установке.

##### demo-app.target

Главная точка входа. Запускает backend и frontend и включается в `multi-user.target` при загрузке системы.

`.target` — это группа, а не healthcheck. Его состояние `active` не гарантирует, что все дочерние сервисы работают. Для проверки нужно использовать `systemctl status` по каждому сервису.

```bash
[Unit]
Description=Demo app group
Wants=demo-app.backend.service demo-app.frontend.service
After=network.target demo-app.backend.service demo-app.frontend.service

[Install]
WantedBy=multi-user.target
```

##### demo-app.backend.service
- запускает `uvicorn main:app` на `${BACKEND_HOST}:${BACKEND_PORT}`;
- читает `.env`;
- работает от пользователя `demo`;
- перезапускается при падении (`Restart=on-failure`, `RestartSec=3`);
- изолирован: `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=...`, `PrivateTmp=yes`.

```bash
[Unit]
Description=Demo Backend (FastAPI)
After=network.target

[Service]
Type=simple
User=demo
Group=demo
WorkingDirectory=@ROOT@/artifacts/current/backend
EnvironmentFile=@ROOT@/.env
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=@ROOT@/artifacts/current/backend/.venv/bin/uvicorn main:app --host ${BACKEND_HOST} --port ${BACKEND_PORT}
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=@PROTECTHOME@
PrivateTmp=yes

[Install]
WantedBy=demo-app.target
```

Переменные `${BACKEND_HOST}` и `${BACKEND_PORT}` берутся из `EnvironmentFile` и подставляются systemd в `ExecStart`.

##### demo-app.frontend.service
- запускает `next start -H ${FRONTEND_HOST} -p ${FRONTEND_PORT}`;
- запускается после backend;
- работает от пользователя `demo`;
- имеет те же настройки перезапуска и изоляции.

```bash
[Unit]
Description=Demo Frontend (Next.js)
After=network.target demo-app.backend.service
Wants=demo-app.backend.service

[Service]
Type=simple
User=demo
Group=demo
WorkingDirectory=@ROOT@/artifacts/current/frontend
EnvironmentFile=@ROOT@/.env
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=NEXT_TELEMETRY_DISABLED=1
ExecStart=@NODE@ @ROOT@/artifacts/current/frontend/node_modules/next/dist/bin/next start -H ${FRONTEND_HOST} -p ${FRONTEND_PORT}
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=@PROTECTHOME@
PrivateTmp=yes

[Install]
WantedBy=demo-app.target
```

`ProtectSystem=strict` делает файловую систему доступной сервису только для чтения. Для текущего демо этого достаточно, но если приложению нужно писать в `.next/cache` или другой каталог, добавьте `ReadWritePaths=`.

##### demo-app.db-init.service
- oneshot-сервис инициализации БД;
- работает от пользователя `postgres`;
- не входит в `demo-app.target`;
- идемпотентен: если база `demo` уже существует, `init-once.sh` пропускает инициализацию;
- после успешного запуска остаётся в состоянии `active` из-за `RemainAfterExit=yes`;
- не зависит от `postgresql.service` явно: `db/init-once.sh` сам ждёт готовности PostgreSQL до 30 секунд.

Запуск вручную:

```shell
sudo systemctl restart demo-app.db-init.service
journalctl -u demo-app.db-init.service -n 50
```

Если юнит ещё ни разу не запускался, подойдёт и `start`. Повторный `start` уже активного юнита ничего не сделает — нужен `restart`. В `install.sh` используется `start`, поэтому при повторной установке уже активный юнит не будет запущен заново.

```bash
[Unit]
Description=Initialize demo-app PostgreSQL database (dev helper)
# Run manually: systemctl start demo-app.db-init.service
After=network-online.target
Wants=network-online.target
ConditionPathExists=@ROOT@/db/init.sql

[Service]
Type=oneshot
RemainAfterExit=yes
User=postgres
ExecStart=@ROOT@/db/init-once.sh
```

---
# Глава 4. Как всем этим управлять
#### 1. Логи и диагностика

```shell
systemctl status demo-app.target
systemctl status demo-app.backend.service
systemctl status demo-app.frontend.service

journalctl -u demo-app.backend.service -n 100 --no-pager
journalctl -u demo-app.frontend.service -n 100 --no-pager
journalctl -u demo-app.db-init.service -n 100 --no-pager

systemctl list-dependencies demo-app.target
systemctl list-units 'demo-app.*' --all
```

`journalctl` для системных юнитов обычно требует root или членства в группе `systemd-journal`.

Проверка backend:

```shell
curl http://127.0.0.1:8000/api/health
```

Если `curl` не установлен:

```shell
wget -qO- http://127.0.0.1:8000/api/health
```

#### 2. Обновление приложения
```shell
sudo ./build.sh
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

Посмотреть доступные версии:

```shell
ls -1 artifacts/
readlink artifacts/current
```

Старые версии в `artifacts/` не удаляются автоматически — их нужно чистить вручную.

#### 3. Откат на предыдущую версию
```shell
ls -1 artifacts/
sudo ln -sfn <REV> artifacts/current
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

---
# Глава 5. Сравнение производительности

Для оценки поведения демо-приложения под systemd и под Docker был проведён набор нагрузочных тестов. Ниже — параметры нагрузки и результаты по пропускной способности.

#### 1. Инструмент и параметры нагрузки

Нагрузка генерировалась утилитой **bombardier** (клиент на fasthttp, HTTP/1.1). Команда запуска:
```Bash
bombardier -c 16 -d 20s -t 10s -l -p result -o json <url>
```

- -c 16 — 16 одновременных TCP-соединений
- -d 20s — длительность прогона
- -t 10s — timeout на один запрос
- -l — сбор статистики задержек
- -p result — без прогресс-бара, только итоговый результат
- -o json — вывод в JSON

Bombardier работает в **closed-loop** режиме. На каждом из 16 соединений выполняется цикл:
1. засекается время
2. отправляется GET
3. полностью читается статус и тело ответа
4. фиксируется latency
5. сразу же отправляется следующий запрос по тому же keep-alive соединению

Следующий запрос уходит только после полного ответа на предыдущий. Поэтому фактический RPS жёстко связан со средней latency:
```
RPS ≈ connections / средняя latency
```

Это хорошо видно на цифрах:

- backend_health — p50 ≈ 7.7 мс → ориентировочно ≈ 2078 RPS, фактически получено ~1900–2000;
- backend_messages — p50 ≈ 105 мс → ориентировочно ≈ 152 RPS, фактически ~150.

Здесь p50 используется как приближение к средней latency.

Нагрузчик не пытался «продавить» сервер сверх 16 одновременных запросов в полёте. Он просто поддерживал 16 активных соединений, а сервер отвечал с той скоростью, с которой мог. Флаг -d 20s — это таймер: по истечении новые запросы не начинаются, но уже начатые дочитываются. Поэтому в JSON timeTakenSeconds обычно получался ≈ 20.08 с.

#### 2. Сценарии и порядок прогонов

| Сценарий         | URL                                    |
| ---------------- | -------------------------------------- |
| backend_health   | GET http://127.0.0.1:8000/api/health   |
| backend_messages | GET http://127.0.0.1:8000/api/messages |
| frontend_ssr     | GET http://127.0.0.1:3000/             |
| frontend_proxy   | GET http://127.0.0.1:3000/api/messages |

В статье приведены результаты только для backend-сценариев; frontend-сценарии использовались для проверки сквозного пути.

Для каждого сценария выполнялась следующая схема:
1. один прогревочный прогон 5 с (результат отбрасывался);
2. три зачётных прогона по 20 с;
3. пауза 1 сек между прогонами;
4. расчёт медианы по трём зачётным результатам.

Прогрев нужен, чтобы вывести TCP-стек, page cache, буферы PostgreSQL и маршруты Next.js в стабильное состояние.

#### 3. Наблюдаемые результаты

По чистой пропускной способности (RPS) устойчивого преимущества одного режима над другим не проявилось. Разница между systemd и Docker лежала в пределах разброса между отдельными раундами одного и того же режима.

Другие метрики — время старта, потребление памяти и размер развёрнутого артефакта — в этой статье не сравниваются.

---

# Глава 6. Вывод

Начиная изучение этой темы, я был уверен, что получу заметный прирост от использования `systemd` вместо Docker. К сожалению, этого не произошло. По сути, это два разных инструмента для разных задач.

Если у вас небольшое или среднее количество сервисов, один или несколько серверов, нет жёстких требований к полной изоляции файловой системы и воспроизводимости окружения «из коробки», а важны минимальные накладные расходы и быстрый старт, то запуск через systemd-юниты показывает себя отлично.

Docker (и особенно Kubernetes) остаётся предпочтительным выбором, когда нужна:
- сильная изоляция и воспроизводимость окружения,
- горизонтальное масштабирование на десятки/сотни узлов,
- единый способ доставки приложения разработчиками и эксплуатации,
- сложная сетевая топология.

Демонстрационный проект показал, что полноценный трёхуровневый стек (Next.js + FastAPI + PostgreSQL) вполне комфортно живёт под systemd. При этом инфраструктурные накладные расходы минимальны: несколько unit-файлов, пара bash-скриптов и обычный Linux.

Главный вывод: не нужно выбирать инструмент по моде. Нужно выбирать его под реальные ограничения задачи. В очень многих случаях «просто systemd» — это не компромисс, а оптимальное решение.
