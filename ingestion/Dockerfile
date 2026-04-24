FROM golang:1.25-alpine AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/ingest ./cmd/ingest

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g 1000 rails && adduser -D -u 1000 -G rails rails
WORKDIR /app
COPY --from=build /out/ingest /app/ingest
COPY static /app/static
# Run as uid 1000 to match the Rails container — we share a SQLite file
# via the mcp_storage volume, so identical ownership is mandatory or
# SQLite writes from Go fail with SQLITE_READONLY.
USER rails

ENV STATIC_DIR=/app/static \
    INGEST_LISTEN=:8081

EXPOSE 8081
ENTRYPOINT ["/app/ingest"]
