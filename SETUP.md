# SecureChat — Backend Setup (Supabase + Cloudinary)

The backend stores all data in **Supabase (PostgreSQL)** and all attachments in
**Cloudinary**. Nothing is persisted on the server's local disk anymore.

## 1. Supabase (database)

1. Create a project at [supabase.com](https://supabase.com).
2. Go to **Project Settings → Database → Connection string → Session pooler**
   (port 5432). It looks like:
   ```
   postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
   ```
3. Put that URI in `backend/.env` as `SUPABASE_DB_URL=`.

**No manual SQL is needed** — the server creates every table and index
idempotently on startup (`users`, `messages`, `groups`, `group_messages`,
`statuses`, `keys`, `files`, `push_tokens`, `otp_codes`). Point it at an empty
database and start the server.

> Note: existing MongoDB data is not migrated automatically. The schema uses
> UUID primary keys, so this is a fresh start by design.

## 2. Cloudinary (attachments)

1. Create a free account at [cloudinary.com](https://cloudinary.com).
2. Dashboard → **Settings → Access Keys** — copy the cloud name, API key and
   API secret into `backend/.env`:
   ```
   CLOUDINARY_CLOUD_NAME=...
   CLOUDINARY_API_KEY=...
   CLOUDINARY_API_SECRET=...
   ```

**How files are protected:** every upload goes to Cloudinary as an
`authenticated` (private) asset under the `securechat/` folder. There is no
public URL. `GET /api/files/<fileId>` authorizes the requester (1:1
participant, group member, or active status) and only then responds with a
302 redirect to a short-lived **signed delivery URL**. E2EE-encrypted
attachments are ciphertext anyway — their AES keys travel only inside the
Signal-encrypted message.

## 3. Run

```bash
cd backend
cp .env.example .env    # then fill in SUPABASE_DB_URL + CLOUDINARY_*
dart pub get
dart run lib/main.dart
```

On boot the server verifies required env vars (`SUPABASE_DB_URL`,
`JWT_SECRET`, `CLOUDINARY_*`, `FIREBASE_PROJECT_ID`), connects to Supabase,
creates the schema, and starts serving.

## 4. Notes for production

- Rotate `JWT_SECRET` if it was ever committed (it was — see git history) and
  consider rewriting history or archiving the repo.
- Set `RATE_LIMIT_TRUST_PROXY=true` when running behind ngrok/nginx/LB so rate
  limits key on the client IP from `X-Forwarded-For`.
- Configure `TURN_SERVER_URL`/`TURN_USERNAME`/`TURN_CREDENTIAL` for reliable
  calls behind symmetric NAT (served to clients via `GET /api/rtc/config`).
- Serve TLS (`TLS_CERT_PATH`/`TLS_KEY_PATH`) — the mobile app's default base
  URL is cleartext HTTP on a LAN IP, which is fine only for development.
- Refresh tokens are now single-active-session: each login/rotation stores the
  new token's `jti` in `users.current_refresh_jti`; older refresh tokens are
  rejected, and `POST /api/auth/logout` invalidates the stored one.
