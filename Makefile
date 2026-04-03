SHELL := /bin/bash

# ---- Variables ----
BACKEND_DIR := backend
JWT_SECRET ?= please_change_me
RAILS_ENV ?= development

# ---- Phonies ----
.PHONY: setup backend-setup backend-db backend-up frontend-up dev rspec lint ci macos-build tauri-build clean

setup: backend-setup ## Install backend deps
	@echo 'Done.'

backend-setup: ## Bundle install & prepare DB
	cd $(BACKEND_DIR) && bundle install
	cd $(BACKEND_DIR) && bin/rails db:create db:migrate

backend-db: ## Reset DB
	cd $(BACKEND_DIR) && bin/rails db:drop db:create db:migrate

backend-up: ## Run Rails API server
	cd $(BACKEND_DIR) && JWT_SECRET=$(JWT_SECRET) bin/rails s

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
