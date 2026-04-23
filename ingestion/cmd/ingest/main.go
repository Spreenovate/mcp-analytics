package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "modernc.org/sqlite"

	"github.com/mcp-analytics/ingestion/internal/ch"
	"github.com/mcp-analytics/ingestion/internal/config"
	"github.com/mcp-analytics/ingestion/internal/ipblock"
	"github.com/mcp-analytics/ingestion/internal/ratelimit"
	"github.com/mcp-analytics/ingestion/internal/server"
	"github.com/mcp-analytics/ingestion/internal/session"
	"github.com/mcp-analytics/ingestion/internal/sites"
	"github.com/mcp-analytics/ingestion/internal/usage"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	cfg := config.FromEnv()

	db, err := sql.Open("sqlite", cfg.SQLitePath+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)")
	if err != nil {
		log.Error("sqlite open failed", "err", err)
		os.Exit(1)
	}
	db.SetMaxOpenConns(4)
	defer db.Close()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	siteCache := sites.New(db, cfg.SiteCacheRefresh, log)
	go siteCache.Run(ctx)

	chClient := ch.New(cfg.ClickHouseURL, cfg.ClickHouseUser, cfg.ClickHousePassword, cfg.ClickHouseDB, log)
	batcher := ch.NewBatcher(chClient, cfg.BatchMaxEvents, cfg.BatchInterval)
	go batcher.Run(ctx)

	usageBuf := usage.NewBuffer(db, cfg.UsageFlushInterval, log)
	go usageBuf.Run(ctx)

	dailySalt := session.NewDailySalt(func() []byte {
		b := make([]byte, 32)
		_, _ = rand.Read(b)
		return b
	})

	limiter := ratelimit.New(cfg.EventsPerSecondPerSite)

	ipBlocker := ipblock.New(ipblock.Options{
		Window:    time.Hour,
		Threshold: 100,
		BlockFor:  time.Hour,
		OnBlock: func(ip string, uniq int, at time.Time) {
			log.Warn("blocking IP for garbage site_ids", "ip", ip, "unique_sites", uniq)
			usageBuf.RecordAbuse(usage.AbuseAlert{
				IP: ip, UniqueSites: uniq,
				BlockedUntil: at.Add(time.Hour), At: at,
			})
		},
	})

	go func() {
		t := time.NewTicker(5 * time.Minute)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				limiter.Sweep(30 * time.Minute)
				ipBlocker.Sweep()
			}
		}
	}()

	srv := &server.Server{
		Log:       log,
		Sites:     siteCache,
		Batcher:   batcher,
		Usage:     usageBuf,
		DailySalt: dailySalt,
		Limiter:   limiter,
		IPBlock:   ipBlocker,
		StaticDir: cfg.StaticDir,
	}

	httpSrv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           srv.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		<-ctx.Done()
		log.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = httpSrv.Shutdown(shutdownCtx)
	}()

	log.Info("ingest listening", "addr", cfg.ListenAddr)
	if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Error("http serve failed", "err", err)
		os.Exit(1)
	}
}
