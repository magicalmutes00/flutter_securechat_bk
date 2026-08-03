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
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Runtime deps (mongo driver uses no native libs; keep image small).
COPY --from=build /app/server /app/server

# .env is mounted from the host; create a writable uploads dir.
RUN mkdir -p /app/uploads && \
    chown -R nobody:nogroup /app

USER nobody

EXPOSE 8080

CMD ["/app/server"]
