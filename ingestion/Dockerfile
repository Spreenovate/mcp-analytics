FROM golang:1.25-alpine AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/ingest ./cmd/ingest && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/reclassify ./cmd/reclassify

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g 1000 rails && adduser -D -u 1000 -G rails rails
WORKDIR /app
COPY --from=build /out/ingest /app/ingest
COPY --from=build /out/reclassify /app/reclassify
COPY static /app/static
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
# Run as uid 1000 to match the Rails container — we share a SQLite file
# via the mcp_storage volume, so identical ownership is mandatory or
# SQLite writes from Go fail with SQLITE_READONLY.
USER rails

ENV STATIC_DIR=/app/static \
    INGEST_LISTEN=:8081

EXPOSE 8081
# entrypoint.sh starts a background loop that re-runs `/app/reclassify
# --apply` on boot + every 24h, then `exec`s ingest as PID 1. See the
# script for the full why-not-cron rationale.
ENTRYPOINT ["/app/entrypoint.sh"]
