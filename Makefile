SHELL := /bin/bash

# ---- Variables ----
BACKEND_DIR := backend
WEB_CLIENT_SRC := clients/web
WEB_CLIENT_DEST := $(BACKEND_DIR)/public/client
# Only these are served; docs and manifests stay out of public/ (see
# backend/spec/public_assets_spec.rb).
WEB_CLIENT_FILES := app.js index.html styles.css
JWT_SECRET ?= please_change_me
RAILS_ENV ?= development
# Rails binds to localhost by default, so a phone on the LAN cannot reach the dev
# server no matter what config.hosts allows. `make backend-up-lan` overrides this.
BIND ?= 127.0.0.1
PORT ?= 5000

# ---- Phonies ----
.PHONY: setup backend-setup backend-db backend-up backend-up-lan frontend-up dev rspec lint ci macos-build tauri-build clean sync-web-client

setup: backend-setup ## Install backend deps
	@echo 'Done.'

backend-setup: ## Bundle install & prepare DB
	cd $(BACKEND_DIR) && bundle install
	cd $(BACKEND_DIR) && bin/rails db:create db:migrate

backend-db: ## Reset DB
	cd $(BACKEND_DIR) && bin/rails db:drop db:create db:migrate

backend-up: ## Run Rails API server
	cd $(BACKEND_DIR) && JWT_SECRET=$(JWT_SECRET) bin/rails s -b $(BIND)

backend-up-lan: ## Run Rails API server reachable from phones/tablets on the LAN
	@ip=$$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $$1}'); \
	echo "Voice client: http://$$ip:$(PORT)/client/"; \
	echo "Rails allows any IP Host in development; *.local is allowed in development.rb."
	$(MAKE) backend-up BIND=0.0.0.0

frontend-up: ## Run web client
	cd clients/web && npm run dev

dev: ## Run both backend and frontend (requires tmux or run in separate terminals)
	@echo "Starting backend and frontend..."
	@echo "Backend will run on http://localhost:5000"
	@echo "Frontend will run on http://localhost:8080"
	@if command -v tmux >/dev/null 2>&1; then \
		tmux new-session -d -s remindly 'cd $(BACKEND_DIR) && JWT_SECRET=$(JWT_SECRET) bin/rails s' \; \
		split-window -h 'cd clients/web && npm run dev' \; \
		attach-session -t remindly; \
	else \
		echo "tmux not found. Please run 'make backend-up' and 'make frontend-up' in separate terminals."; \
	fi

sync-web-client: ## Copy the voice web client into backend/public/client (clients/web is authoritative)
	@mkdir -p "$(WEB_CLIENT_DEST)"
	@set -e; for f in $(WEB_CLIENT_FILES); do \
		cp "$(WEB_CLIENT_SRC)/$$f" "$(WEB_CLIENT_DEST)/$$f"; \
		echo "synced $$f"; \
	done

rspec: ## Run Rails specs
	cd $(BACKEND_DIR) && bundle exec rspec

lint: ## Placeholder for rubocop/eslint
	@echo 'Add rubocop/eslint here.'

ci: rspec ## CI entrypoint

macos-build: ## Xcode build (placeholder)
	@echo 'Open clients/macos-swiftui in Xcode and build.'

tauri-build: ## Tauri build (placeholder)
	@echo 'Run pnpm tauri build inside clients/tauri when added.'

clean: ## Remove temp artifacts
	rm -rf tmp log
