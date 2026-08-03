# SecureChat — Backend Server

A production-ready Dart server built on `shelf`, providing REST APIs, an
authenticated WebSocket, E2EE key bundles, group messaging, WebRTC call
signaling, status stories, and push notifications.

## Prerequisites

- Dart SDK 3.x
- MongoDB 6/7 running locally or via Docker

## Running locally

```sh
cp .env.example .env      # then fill in secrets (JWT_SECRET, etc.)
dart pub get
dart run lib/main.dart
```

The server binds `SERVER_HOST:SERVER_PORT` (default `0.0.0.0:8080`) and exposes
`/health`.

## Docker

```sh
# Build and run backend + MongoDB together
docker compose up --build

# Or build just the image
docker build -t securechat/backend .
```

`docker-compose.yml` wires the backend to a `mongo` service via Docker health
checks, mounts uploads, and loads secrets from `.env`.

## TLS

Set `TLS_CERT_PATH` and `TLS_KEY_PATH` to PEM file paths and the server binds
HTTPS instead of plain HTTP. For production, TLS often terminates at a reverse
proxy (Caddy/nginx) in front of the container.

## Push notifications (FCM)

The backend stores per-user device tokens (via `/api/push/`) and dispatches FCM
notifications to offline recipients when messages are delivered. Set
`FCM_SERVER_KEY`. If unset, push dispatch silently no-ops.

## API surface (protected by bearer token unless noted)

- `/api/auth/*` — profile, contacts sync (public: OTP, login/refresh)
- `/api/chat/*` — messages, conversations, search
- `/api/files/*` — authed upload/download
- `/api/keys/*` — E2EE key bundles
- `/api/groups/*` — group CRUD + group messages
- `/api/status/*` — status stories
- `/api/push/*` — device push-token registration

## Tests

```sh
dart test
```