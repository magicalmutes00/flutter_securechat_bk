# --- Build stage: resolve deps and compile a self-contained binary ---
FROM dart:stable AS build

WORKDIR /app

# Fetch dependencies first for better layer caching.
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline && \
    dart compile exe lib/main.dart -o /app/server

# --- Runtime stage ---
# The Postgres driver and Cloudinary uploads need no native libs and no local
# writable storage, so the runtime image stays minimal.
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/server /app/server

RUN chown -R nobody:nogroup /app

USER nobody

# Render injects PORT (default 10000) and the server picks it up when
# SERVER_PORT is unset; 8080 is the local/docker default.
EXPOSE 8080

CMD ["/app/server"]
