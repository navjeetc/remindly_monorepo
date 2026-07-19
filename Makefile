SHELL := /bin/bash

# ---- Variables ----
BACKEND_DIR := backend
JWT_SECRET ?= please_change_me
RAILS_ENV ?= development
# Rails binds to localhost by default, so a phone on the LAN cannot reach the dev
# server no matter what config.hosts allows. `make backend-up-lan` overrides this.
BIND ?= 127.0.0.1
PORT ?= 5000

# ---- Phonies ----
.PHONY: setup backend-setup backend-db backend-up backend-up-lan dev rspec lint ci macos-build tauri-build clean

setup: backend-setup ## Install backend deps
	@echo 'Done.'

backend-setup: ## Bundle install & prepare DB
	cd $(BACKEND_DIR) && bundle install
	cd $(BACKEND_DIR) && bin/rails db:create db:migrate

backend-db: ## Reset DB
	cd $(BACKEND_DIR) && bin/rails db:drop db:create db:migrate

backend-up: ## Run Rails API server
	cd $(BACKEND_DIR) && JWT_SECRET=$(JWT_SECRET) bin/rails s -b $(BIND) -p $(PORT)

backend-up-lan: ## Run Rails API server reachable from phones/tablets on the LAN
	@ip=$$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $$1}'); \
	echo "Voice reminders: http://$$ip:$(PORT)/voice_reminders"; \
	echo "Rails allows any IP Host in development; *.local is allowed in development.rb."
	$(MAKE) backend-up BIND=0.0.0.0

# There is no separate frontend process any more: Rails serves the voice client
# at /voice_reminders. `make dev` is kept as an alias for the backend.
dev: ## Run the app (Rails serves the dashboard and the voice client)
	@echo "Dashboard:       http://localhost:$(PORT)/dashboard"
	@echo "Voice reminders: http://localhost:$(PORT)/voice_reminders"
	$(MAKE) backend-up

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
