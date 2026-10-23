# Microservices on systemd

Демонстрационный проект: Next.js + FastAPI + PostgreSQL, развёрнутый и управляемый через systemd без Docker.

Проект показывает, как собрать фронтенд и бэкенд в версионированные артефакты, запустить их как отдельные systemd-сервисы от непривилегированного пользователя и объединить в одну группу через `.target`.

## Архитектура

```text
Браузер
  │ HTTP :3000
  ▼
Next.js (frontend) ──HTTP :8000──▶ FastAPI (backend) ──TCP :5432──▶ PostgreSQL
```

- **Frontend** — Next.js 14, серверный рендеринг страницы со списком сообщений.
- **Backend** — FastAPI, эндпоинты `/api/health` и `/api/messages`.
- **Database** — PostgreSQL, база `demo`, таблица `messages`.
- **systemd** — запуск, автозапуск, перезапуск при падении и базовая изоляция сервисов.

## Состав проекта

```text
.
├── .env.example                 # шаблон конфигурации
├── build.sh                     # сборка версионированных артефактов
├── install.sh                   # установка и первый запуск
├── uninstall.sh                 # удаление systemd-юнитов
├── db/
│   ├── init.sql                 # создание БД, пользователя и таблицы
│   └── init-once.sh             # идемпотентная инициализация БД
├── scripts/
│   ├── install-deps.sh          # установка зависимостей под разные дистрибутивы
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

## Требования

- Linux с systemd (не подходит окружение без PID 1 systemd, например обычный WSL без systemd).
- Права root или sudo для установки.
- Python 3 с модулем `venv`. Желателен `ensurepip`; если его нет, `build.sh` установит pip через `get-pip.py`.
- Node.js 18.17+ и npm.
- PostgreSQL.
- `wget` или `curl` — нужен только для fallback-установки pip, если `ensurepip` отсутствует.

Скрипт `scripts/install-deps.sh` умеет ставить зависимости в Debian/Ubuntu, RHEL/Fedora/CentOS, Arch, openSUSE/SLES и ALT Linux.

## Быстрый старт

```bash
git clone <repo> microservices-on-systemd
cd microservices-on-systemd

cp .env.example .env
sudo ./install.sh
```

После установки:

- frontend: `http://<IP-сервера>:3000`
- backend health check: `http://127.0.0.1:8000/api/health`

Проверка состояния:

```bash
systemctl status demo-app.target
systemctl status demo-app.backend.service demo-app.frontend.service
systemctl list-units 'demo-app.*' --all
```

## Конфигурация

Настройки хранятся в `.env`:

```dotenv
DB_DSN=postgresql://demo:demo@localhost:5432/demo

BACKEND_HOST=127.0.0.1
BACKEND_PORT=8000

FRONTEND_HOST=0.0.0.0
FRONTEND_PORT=3000
```

| Переменная | Назначение | По умолчанию |
|---|---|---|
| `DB_DSN` | строка подключения backend к PostgreSQL | `postgresql://demo:demo@localhost:5432/demo` |
| `BACKEND_HOST` | адрес, на котором слушает backend | `127.0.0.1` |
| `BACKEND_PORT` | порт backend | `8000` |
| `FRONTEND_HOST` | адрес, на котором слушает frontend | `0.0.0.0` |
| `FRONTEND_PORT` | порт frontend | `3000` |

`.env` не хранится в git. `.env.example` содержит демонстрационные значения и не содержит реальных секретов.

`BACKEND_HOST` и `BACKEND_PORT` используются в двух местах:

- backend слушает на этом адресе;
- frontend ходит на этот адрес за данными.

`BACKEND_HOST=127.0.0.1` означает, что backend доступен только с самого сервера. `FRONTEND_HOST=0.0.0.0` означает, что frontend доступен по всем сетевым интерфейсам.

После изменения `.env`:

- для смены адреса или порта backend/frontend достаточно перезапустить сервисы;
- для изменения rewrite-правила `/api/*` в Next.js нужна пересборка, потому что оно вычисляется при `npm run build`.

```bash
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

## Как работает установка

`install.sh` выполняет следующие шаги:

1. Определяет корень проекта `ROOT`.
2. Устанавливает системные зависимости.
3. Создаёт системного пользователя и группу `demo`.
4. Выставляет права на `.env`.
5. Разрешает пользователям `demo` и `postgres` проход по родительским каталогам проекта.
6. Включает и запускает PostgreSQL, при необходимости инициализирует кластер.
7. Добавляет в `pg_hba.conf` локальную peer-аутентификацию для пользователя `postgres`.
8. Рендерит systemd-юниты из `systemd/` в `/etc/systemd/system/`.
9. Останавливает ранее запущенные backend и frontend.
10. Собирает артефакты, если `artifacts/current` ещё не существует.
11. Инициализирует демонстрационную БД.
12. Включает и запускает `demo-app.target`.

Повторный `install.sh` не пересобирает уже существующие артефакты. Для обновления кода используйте `build.sh`.

## Сборка и артефакты

`build.sh` создаёт отдельную версию приложения в `artifacts/<REV>`:

```text
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

## systemd-юниты

### `demo-app.target`

Главная точка входа. Запускает backend и frontend, включается при загрузке системы.

```ini
[Unit]
Wants=demo-app.backend.service demo-app.frontend.service
After=network.target demo-app.backend.service demo-app.frontend.service

[Install]
WantedBy=multi-user.target
```

`.target` — это группа, а не healthcheck. Его состояние `active` не гарантирует, что все дочерние сервисы работают. Для проверки используйте `systemctl status` по каждому сервису.

### `demo-app.backend.service`

- запускает `uvicorn main:app` на `${BACKEND_HOST}:${BACKEND_PORT}`;
- читает `.env`;
- работает от пользователя `demo`;
- перезапускается при падении (`Restart=on-failure`, `RestartSec=3`);
- изолирован: `NoNewPrivileges=yes`, `ProtectSystem=strict`, `PrivateTmp=yes`.

### `demo-app.frontend.service`

- запускает `next start -H ${FRONTEND_HOST} -p ${FRONTEND_PORT}`;
- запускается после backend;
- работает от пользователя `demo`;
- имеет те же настройки перезапуска и изоляции.

### `demo-app.db-init.service`

- oneshot-сервис инициализации БД;
- работает от пользователя `postgres`;
- не входит в `demo-app.target`;
- повторный запуск безопасен: если база `demo` уже существует, инициализация пропускается.

Запуск вручную:

```bash
sudo systemctl start demo-app.db-init.service
journalctl -u demo-app.db-init.service -n 50
```

## Поток запроса

1. Браузер запрашивает `http://<сервер>:3000`.
2. Next.js выполняет серверный компонент страницы.
3. Компонент запрашивает `http://${BACKEND_HOST}:${BACKEND_PORT}/api/messages`.
4. FastAPI подключается к PostgreSQL по `DB_DSN`.
5. PostgreSQL возвращает строки из таблицы `messages`.
6. FastAPI отдаёт JSON.
7. Next.js рендерит HTML и возвращает его браузеру.

Дополнительно Next.js проксирует запросы `/api/*` на backend через `rewrites` в `next.config.js`.

## Обновление приложения

```bash
sudo ./build.sh
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

Посмотреть доступные версии:

```bash
ls -1 artifacts/
readlink artifacts/current
```

## Откат на предыдущую версию

```bash
ls -1 artifacts/
sudo ln -sfn <REV> artifacts/current
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

## Логи и диагностика

```bash
systemctl status demo-app.target
systemctl status demo-app.backend.service
systemctl status demo-app.frontend.service

journalctl -u demo-app.backend.service -n 100 --no-pager
journalctl -u demo-app.frontend.service -n 100 --no-pager
journalctl -u demo-app.db-init.service -n 100 --no-pager

systemctl list-dependencies demo-app.target
systemctl list-units 'demo-app.*' --all
```

Проверка backend:

```bash
curl http://127.0.0.1:8000/api/health
```

Если `curl` не установлен:

```bash
wget -qO- http://127.0.0.1:8000/api/health
```

## Частые проблемы

### `The virtual environment was not created successfully because ensurepip is not available`

Не установлен пакет `python3-venv` или отсутствует `ensurepip`.

Решение:

```bash
sudo apt install python3-venv
```

Либо пересоберите проект: `build.sh` умеет устанавливать pip через `get-pip.py`, если есть `wget` или `curl`.

### `must run as root`

`install.sh`, `uninstall.sh` и `scripts/install-*.sh` требуют root:

```bash
sudo ./install.sh
```

`build.sh` можно запускать без root, если каталог `artifacts` доступен на запись текущему пользователю.

### `artifacts/current exists; run build.sh to refresh`

Это не ошибка. `install.sh` не пересобирает существующие артефакты. Для обновления:

```bash
sudo ./build.sh
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

### Target активен, но приложение не работает

Проверьте дочерние сервисы:

```bash
systemctl status demo-app.backend.service demo-app.frontend.service
journalctl -u demo-app.backend.service -n 100 --no-pager
```

### Frontend не получает данные

Проверьте:

```bash
systemctl status demo-app.backend.service
curl http://127.0.0.1:8000/api/health
```

Также убедитесь, что `BACKEND_HOST` и `BACKEND_PORT` в `.env` совпадают с адресом, на котором слушает backend.

### Порт уже занят

Измените `BACKEND_PORT` или `FRONTEND_PORT` в `.env` и перезапустите сервисы. Для frontend при смене адреса backend также потребуется пересборка, если используется rewrite `/api/*`.

## Удаление

```bash
sudo ./uninstall.sh
```

Скрипт:

- останавливает и отключает сервисы;
- удаляет юниты из `/etc/systemd/system/`;
- выполняет `daemon-reload`.

Не удаляются:

- собранные артефакты в `artifacts/`;
- `.env`;
- пользователь `demo`;
- база данных и данные PostgreSQL.

Полная очистка выполняется вручную и требует осторожности:

```bash
sudo userdel demo
sudo -u postgres dropdb demo
sudo -u postgres dropuser demo
sudo rm -rf artifacts
```

## Безопасность и ограничения

Проект предназначен для демонстрации и курсовой работы, а не для production.

- Пароль `demo/demo` и хранение `DB_DSN` в `.env` — только для демо.
- Нет TLS, аутентификации пользователей и авторизации API.
- Frontend по умолчанию доступен по всем интерфейсам (`0.0.0.0`).
- `.target` не агрегирует состояние дочерних сервисов и не заменяет healthcheck.
- `db/init.sql` не является системой миграций: при существующей БД изменения схемы не применяются.
- Старые артефакты не удаляются автоматически.
- Systemd-изоляция (`ProtectSystem`, `ProtectHome`, `PrivateTmp`, `NoNewPrivileges`) снижает риски, но не заменяет контейнерную изоляцию.

## Полезные команды

```bash
# установка
cp .env.example .env
sudo ./install.sh

# пересборка
sudo ./build.sh

# перезапуск приложения
sudo systemctl restart demo-app.backend.service demo-app.frontend.service

# состояние
systemctl status demo-app.target
systemctl status demo-app.backend.service demo-app.frontend.service

# логи
journalctl -u demo-app.backend.service -f
journalctl -u demo-app.frontend.service -f

# инициализация БД вручную
sudo systemctl start demo-app.db-init.service

# удаление юнитов
sudo ./uninstall.sh
```
