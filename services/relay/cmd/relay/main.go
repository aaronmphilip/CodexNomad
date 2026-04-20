package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/codexnomad/codexnomad/services/relay/internal/config"
	"github.com/codexnomad/codexnomad/services/relay/internal/httpapi"
	"github.com/codexnomad/codexnomad/services/relay/internal/provisioning"
	"github.com/codexnomad/codexnomad/services/relay/internal/supabase"
	"github.com/codexnomad/codexnomad/services/relay/internal/webhook"
	"github.com/codexnomad/codexnomad/services/relay/internal/ws"
)

func main() {
	if err := run(); err != nil {
		log.Printf("fatal: %v", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	store := supabase.New(cfg.SupabaseURL, cfg.SupabaseServiceRoleKey)
	prov := provisioning.New(cfg, store)
	hooks := webhook.New(cfg, store, prov)
	hub := ws.NewHub(cfg)
	api := httpapi.New(cfg, hub, store, prov, hooks)

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           api.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       90 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go prov.RunCleanupWorker(ctx)

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	log.Printf("codexnomad relay listening on :%s", cfg.Port)
	err = server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
