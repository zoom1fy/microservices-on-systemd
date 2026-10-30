# Microservices on systemd

Небольшой проект для практики: Next.js, FastAPI и PostgreSQL, всё запускается через systemd. Docker не используется.

```text
браузер → Next.js :3000 → FastAPI :8000 → PostgreSQL :5432
```

## Что внутри

- `frontend` — Next.js 14, страница со списком сообщений.
- `backend` — FastAPI, `/api/health` и `/api/messages`.
- `database` — PostgreSQL, база `demo` и таблица `messages`.
- `systemd` — отдельные сервисы для frontend и backend, плюс общий target.

## Структура

```text
.
├── .env.example                 # пример конфига
├── build.sh                     # сборка артефактов
├── install.sh                   # установка и первый запуск
├── uninstall.sh                 # удаление сервисов
├── db/
│   ├── init.sql                 # база, пользователь, таблица
│   └── init-once.sh             # инициализация БД
├── scripts/
│   ├── install-deps.sh          # установка пакетов через apt
│   └── install-systemd-units.sh # установка юнитов
├── src/
│   ├── backend/
│   └── frontend/
└── systemd/
    ├── demo-app.target
    ├── demo-app.backend.service
    ├── demo-app.frontend.service
    └── demo-app.db-init.service
```

## Требования

Debian или Ubuntu с systemd и доступом к root. Для Next.js 14 нужен Node 18.17+.

Системные пакеты:

```text
nodejs npm python3 python3-venv postgresql postgresql-client
```

`install.sh` поставит их сам через `apt`, если чего-то не хватает.

## Установка

```bash
cp .env.example .env
sudo ./install.sh
```

После установки приложение будет доступно на `http://<ip>:3000`, а health check backend — на `http://127.0.0.1:8000/api/health`.

`install.sh` не пересобирает уже готовые артефакты. Если `artifacts/current` существует, сборку нужно запускать отдельно.

## Настройки

Все параметры лежат в `.env`:

```dotenv
DB_DSN=postgresql://demo:demo@localhost:5432/demo

BACKEND_HOST=127.0.0.1
BACKEND_PORT=8000

FRONTEND_HOST=0.0.0.0
FRONTEND_PORT=3000
```

После изменения адреса или порта достаточно перезапустить сервисы:

```bash
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

## Как проходит установка

`install.sh` ставит пакеты, создаёт пользователя `demo`, запускает PostgreSQL и добавляет локальную peer-аутентификацию для `postgres`. Дальше устанавливает systemd-юниты, собирает артефакты, если их ещё нет, инициализирует базу и запускает `demo-app.target`.

## Сборка и обновление

```bash
sudo ./build.sh
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

Каждая сборка попадает в `artifacts/<REV>`, где `REV` — время сборки. Симлинк `artifacts/current` указывает на актуальную версию.

Откатиться на старую сборку можно так:

```bash
ls -1 artifacts/
sudo ln -sfn <REV> artifacts/current
sudo systemctl restart demo-app.backend.service demo-app.frontend.service
```

## systemd

`demo-app.target` — точка входа, которая поднимает backend и frontend. Сервисы работают от пользователя `demo`, перезапускаются при падении и имеют базовую изоляцию.

`demo-app.db-init.service` — отдельный oneshot для инициализации БД. В target он не входит, повторный запуск безопасен.

Основные команды:

```bash
systemctl status demo-app.target
systemctl status demo-app.backend.service demo-app.frontend.service
systemctl list-units 'demo-app.*' --all
```

Важно: активный target не означает, что оба сервиса живы. Состояние нужно смотреть по каждому сервису отдельно.

## Логи

```bash
journalctl -u demo-app.backend.service -n 100 --no-pager
journalctl -u demo-app.frontend.service -n 100 --no-pager
journalctl -u demo-app.db-init.service -n 100 --no-pager
```

## Удаление

```bash
sudo ./uninstall.sh
```

Скрипт останавливает сервисы и удаляет юниты. Артефакты, `.env`, пользователь `demo` и база остаются.

Если нужно вычистить всё:

```bash
sudo userdel demo
sudo -u postgres dropdb demo
sudo -u postgres dropuser demo
sudo rm -rf artifacts
```