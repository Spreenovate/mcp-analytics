FROM golang:1.24-alpine AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/ingest ./cmd/ingest

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S app && adduser -S -G app app
WORKDIR /app
COPY --from=build /out/ingest /app/ingest
COPY static /app/static
USER app

ENV STATIC_DIR=/app/static \
    INGEST_LISTEN=:8081

EXPOSE 8081
ENTRYPOINT ["/app/ingest"]
