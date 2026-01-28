# Houston - Development Makefile
# Quick commands for common development tasks

.PHONY: help init run dev build start stop restart logs logs-rails logs-db clean reset test shell status status-docker migrate db-prepare
.PHONY: magic-link invite-code demo-account
.PHONY: add-mcp add-mcp-json mcp-status mcp-probe
.PHONY: test-smoke test-file test-llm-provider test-llm-create-goal test-llm-goal test-llm-user-agent test-llm-goal-task
.PHONY: ios-check ios-check-clean ios-check-verbose ios-build-device ios-build-device-clean ios-build-device-verbose ios-beta ios-beta-dry

# Detect Docker Compose command (v2 "docker compose" or legacy "docker-compose")
ifeq ($(shell docker compose version >/dev/null 2>&1 && echo ok),ok)
  COMPOSE := docker compose
else ifeq ($(shell docker-compose version >/dev/null 2>&1 && echo ok),ok)
  COMPOSE := docker-compose
else
  $(error Neither 'docker compose' nor 'docker-compose' is available. Please install Docker Desktop, Colima + Compose, or Docker Compose.)
endif

# Detect buildx availability; if missing, fall back to legacy build flags
ifeq ($(shell docker buildx version >/dev/null 2>&1 && echo ok),ok)
  BUILD_ENV :=
else
  # Fall back to classic builder (avoids Bake/buildx warnings)
  BUILD_ENV := DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0
endif

# Portable in-place sed (macOS/BSD vs Linux GNU sed)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  SED_INPLACE := sed -i '' -e
else
  SED_INPLACE := sed -i -e
endif

# Default target
help:
	@echo "🚀 Houston - Quick Start:"
	@echo "  make init      - Copy .env.example to .env, generate secrets"
	@echo "  make start     - Start all services (background, auto-restarts)"
	@echo "  make stop      - Stop all services"
	@echo ""
	@echo "💻 Development:"
	@echo "  make dev       - Start with logs (foreground)"
	@echo "  make restart   - Restart all services"
	@echo "  make logs      - View logs"
	@echo "  make shell     - Rails console"
	@echo "  make status    - Check system health"
	@echo ""
	@echo "🧪 Testing:"
	@echo "  make test      - Run all tests (mocked, free)"
	@echo "  make test-smoke - Critical path tests only"
	@echo ""
	@echo "🛠️  Utilities:"
	@echo "  make migrate   - Run migrations"
	@echo "  make clean     - Remove containers (keeps data)"
	@echo "  make reset     - Complete reset + rebuild"
	@echo ""
	@echo "📱 iOS:"
	@echo "  make ios-check        - Validate iOS compilation"
	@echo "  make ios-build-device - Build & deploy to device"
	@echo "  make ios-beta         - Build & upload to TestFlight"
	@echo "  make ios-beta-dry     - Preview TestFlight deployment (no upload)"
	@echo "  make demo-account     - Create demo account for Apple review"
	@echo ""
	@echo "💡 Tunnel: Set NGROK_DOMAIN and NGROK_AUTHTOKEN in .env to auto-start ngrok"
	@echo ""
	@echo "For more commands: grep '^[a-z-]*:' Makefile"

# ============================================================================
# Setup Commands
# ============================================================================

# Initialize secrets only (no user input required)
init:
	@echo "🔐 Initializing Houston..."
	@chmod +x scripts/init_secrets.sh
	@./scripts/init_secrets.sh

# Quick start - init if needed, then start
run:
	@if [ ! -f .env ] || grep -qE '^SECRET_KEY_BASE=\s*$$' .env 2>/dev/null; then \
		$(MAKE) init; \
	fi
	@$(MAKE) start

# Generate Rails secrets (deprecated - use 'make init')
secrets: init
	@echo "⚠️  Note: 'make secrets' is deprecated. Use 'make init' instead."

dev:
	@echo "🧑‍💻 Starting development environment..."
	@NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env 2>/dev/null | cut -d= -f2); \
	NGROK_AUTH=$$(grep '^NGROK_AUTHTOKEN=' .env 2>/dev/null | cut -d= -f2); \
	if [ -n "$$NGROK_DOMAIN" ] && [ -n "$$NGROK_AUTH" ]; then \
		echo "🌐 ngrok tunnel enabled (https://$$NGROK_DOMAIN)"; \
		$(BUILD_ENV) $(COMPOSE) --profile tunnel up --build; \
	else \
		$(BUILD_ENV) $(COMPOSE) up --build; \
	fi

# Start all services in background (auto-restarts after reboot)
start:
	@# Validate environment configuration
	@chmod +x scripts/check_env.sh
	@./scripts/check_env.sh || exit 1
	@# Start services
	@echo "▶️  Starting all services..."
	@NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env 2>/dev/null | cut -d= -f2); \
	NGROK_AUTH=$$(grep '^NGROK_AUTHTOKEN=' .env 2>/dev/null | cut -d= -f2); \
	if [ -n "$$NGROK_DOMAIN" ] && [ -n "$$NGROK_AUTH" ]; then \
		$(BUILD_ENV) $(COMPOSE) --profile tunnel up -d --build; \
	else \
		$(BUILD_ENV) $(COMPOSE) up -d --build; \
	fi
	@# Wait for backend to be healthy
	@echo "⏳ Waiting for services..."
	@sleep 5
	@# Run migrations
	@$(COMPOSE) exec backend bundle exec rails db:migrate 2>/dev/null || true
	@# Check if admin user exists, if not prompt to create one
	@ADMIN_EXISTS=$$($(COMPOSE) exec -T backend bundle exec rails runner "puts User.where(role: 'admin').exists?" 2>/dev/null | grep -v "Sidekiq\|INFO\|pid=" | tr -d '\r'); \
	if [ "$$ADMIN_EXISTS" != "true" ]; then \
		echo ""; \
		echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
		echo "  No admin user found - let's create one"; \
		echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
		echo ""; \
		printf "  Enter your email address: "; \
		read ADMIN_EMAIL; \
		if [ -n "$$ADMIN_EMAIL" ]; then \
			echo "  Creating admin user..."; \
			INVITE_CODE=$$($(COMPOSE) exec -T -e EMAIL="$$ADMIN_EMAIL" backend bundle exec rails runner " \
				email = ENV.fetch('EMAIL').strip.downcase; \
				user = User.find_or_create_by!(email: email); \
				user.update!(role: 'admin') unless user.admin?; \
				invite = user.invite_tokens.build; \
				code = invite.set_token!; \
				invite.save!; \
				puts code; \
			" 2>/dev/null | grep -v "Sidekiq\|INFO\|pid=" | tr -d '\r'); \
			if [ -n "$$INVITE_CODE" ]; then \
				SERVER_PUBLIC_URL=$$(grep '^SERVER_PUBLIC_URL=' .env 2>/dev/null | cut -d= -f2); \
				NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env 2>/dev/null | cut -d= -f2); \
				EMAIL_PROVIDER=$$(grep '^EMAIL_PROVIDER=' .env 2>/dev/null | cut -d= -f2); \
				PORT=$$(grep '^PORT=' .env 2>/dev/null | cut -d= -f2); \
				PORT=$${PORT:-3033}; \
				if [ -n "$$SERVER_PUBLIC_URL" ]; then \
					SERVER_URL="$$SERVER_PUBLIC_URL"; \
				elif [ -n "$$NGROK_DOMAIN" ]; then \
					SERVER_URL="https://$$NGROK_DOMAIN"; \
				else \
					SERVER_URL="http://localhost:$$PORT"; \
				fi; \
				echo ""; \
				echo "  ✅ Admin user created!"; \
				echo ""; \
				if [ -n "$$EMAIL_PROVIDER" ]; then \
					$(COMPOSE) exec -T -e EMAIL="$$ADMIN_EMAIL" -e SERVER_URL="$$SERVER_URL" backend bundle exec rails runner " \
						user = User.find_by!(email: ENV['EMAIL'].strip.downcase); \
						server_url = ENV['SERVER_URL']; \
						server_name = ENV['SERVER_DISPLAY_NAME'].presence || (URI.parse(server_url).host rescue 'Houston'); \
						helper = Class.new { include JwtAuth }.new; \
						token = helper.issue_signin_token(user.email, context: 'app'); \
						MagicLinkMailer.with(user: user, token: token, server_url: server_url, server_name: server_name).app_signin.deliver_now; \
					" 2>/dev/null; \
					echo "  ┌─────────────────────────────────────────────────────┐"; \
					echo "  │  📧 Check your email for an iOS app sign-in link    │"; \
					echo "  │                                                     │"; \
					echo "  │  For admin dashboard, use this invite code:         │"; \
					echo "  │                                                     │"; \
					echo "  │     URL:   $$SERVER_URL/admin"; \
					echo "  │     Email: $$ADMIN_EMAIL"; \
					echo "  │     Code:  $$INVITE_CODE"; \
					echo "  │                                                     │"; \
					echo "  │  Code valid for 24 hours after first use.           │"; \
					echo "  └─────────────────────────────────────────────────────┘"; \
				else \
					echo "  ┌─────────────────────────────────────────────────────┐"; \
					echo "  │  To sign in from the iOS app:                       │"; \
					echo "  │                                                     │"; \
					echo "  │  1. Open Houston app                                │"; \
					echo "  │  2. Tap 'Use server invite code'                    │"; \
					echo "  │  3. Enter:                                          │"; \
					echo "  │     Server: $$SERVER_URL"; \
					echo "  │     Email:  $$ADMIN_EMAIL"; \
					echo "  │     Code:   $$INVITE_CODE"; \
					echo "  │                                                     │"; \
					echo "  │  Same code works for admin dashboard at:            │"; \
					echo "  │     $$SERVER_URL/admin"; \
					echo "  │                                                     │"; \
					echo "  │  Code valid for 24 hours after first use.           │"; \
					echo "  └─────────────────────────────────────────────────────┘"; \
				fi; \
				echo ""; \
			else \
				echo "  ⚠️  Failed to create user"; \
			fi; \
		else \
			echo "  Skipped - run 'make invite-code EMAIL=you@example.com' later"; \
		fi; \
	fi
	@# Print summary
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  ✅ Houston is running!"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@PORT=$$(grep '^PORT=' .env 2>/dev/null | cut -d= -f2); \
	PORT=$${PORT:-3033}; \
	NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env 2>/dev/null | cut -d= -f2); \
	echo ""; \
	echo "  Local:   http://localhost:$$PORT"; \
	if [ -n "$$NGROK_DOMAIN" ]; then \
		echo "  Public:  https://$$NGROK_DOMAIN"; \
	fi; \
	echo ""; \
	echo "  make logs   - View logs"; \
	echo "  make stop   - Stop services"; \
	echo "  make shell  - Rails console"; \
	echo ""

# Stop all services
stop:
	@echo "⏹️  Stopping all services..."
	$(COMPOSE) --profile tunnel down

# Restart all services
restart: stop start

# Build containers
build:
	@echo "🔨 Building containers..."
	$(BUILD_ENV) $(COMPOSE) build

# Show logs from all services
logs:
	$(COMPOSE) logs -f

# Show only Rails logs
logs-rails:
	$(COMPOSE) logs -f backend

# Show only database logs  
logs-db:
	$(COMPOSE) logs -f postgres

# Open Rails console
shell:
	$(COMPOSE) exec backend bundle exec rails console

#############################################
# Testing Commands - Organized by Speed & Cost
#############################################

# Fast, Free Tests (Mocked)
test:
	@echo "🧪 Running all tests (mocked, fast, free)"
	$(COMPOSE) exec -e RAILS_ENV=test backend bundle exec rails db:prepare && \
	$(COMPOSE) exec -e RAILS_ENV=test backend bundle exec rspec

test-smoke:
	@echo "🔥 Running smoke tests (critical path + orchestrator startup)"
	@echo "   These tests catch basic errors without making LLM calls"
	$(COMPOSE) exec -e RAILS_ENV=test backend bundle exec rails db:prepare && \
	$(COMPOSE) exec -e RAILS_ENV=test backend bundle exec rspec --tag core

#############################################
# Real LLM Tests - Component Specific
# ⚠️  These make actual API calls and cost money!
#############################################

# Sanity check - cheapest possible LLM test
test-llm-provider:
	@echo "⚠️  Testing LLM provider connectivity (minimal cost ~\$$0.001)"
	@echo "🔑 Requires ANTHROPIC_API_KEY or OPENAI_API_KEY"
	@echo ""
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rails db:prepare && \
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rspec spec/services/llms/service_spec.rb --tag provider --format documentation

# Goal creation workflow - chat + extraction
test-llm-create-goal:
	@echo "⚠️  Testing goal creation workflow (~\$$0.02-0.05)"
	@echo "🎯 Tests: Goal creation chat, learnings extraction, agent instructions"
	@echo "💰 Makes actual LLM API calls"
	@echo ""
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rails db:prepare && \
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rspec spec/workflows/goal_creation_workflow_spec.rb --tag real_llm --format documentation

# Goal agent conversation workflow
test-llm-goal:
	@echo "⚠️  Testing goal agent workflow (~\$$0.03-0.07)"
	@echo "🎯 Tests: Goal agent, thread messages, task creation"
	@echo "💰 Makes actual LLM API calls"
	@echo ""
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rails db:prepare && \
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rspec spec/workflows/goal_agent_workflow_spec.rb --tag real_llm --format documentation

# User agent conversation workflow
test-llm-user-agent:
	@echo "⚠️  Testing user agent workflow (~\$$0.02-0.04)"
	@echo "🎯 Tests: User agent, learnings, web search, thread messages"
	@echo "💰 Makes actual LLM API calls"
	@echo ""
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rails db:prepare && \
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rspec spec/workflows/user_agent_workflow_spec.rb --tag real_llm --format documentation

# Goal → Task → Note complete workflow
test-llm-goal-task:
	@echo "⚠️  Testing Goal → Task → Note workflow (~\$$0.05-0.10)"
	@echo "🎯 Tests: Goal creates task, task completes and creates note"
	@echo "💰 Makes actual LLM API calls"
	@echo ""
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rails db:prepare && \
	$(COMPOSE) exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rspec spec/workflows/goal_task_workflow_spec.rb --tag real_llm --format documentation


# Run specific test file (usage: make test-file FILE=spec/models/goal_spec.rb)
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "❌ Error: Please specify FILE=path/to/spec.rb"; \
		exit 1; \
	fi; \
	echo "🧪 Running test file: $(FILE)"; \
	$(COMPOSE) exec -e RAILS_ENV=test backend bundle exec rails db:prepare && $(COMPOSE) exec -e RAILS_ENV=test backend bundle exec rspec $(FILE)


# Clean up containers (volumes preserved)
clean:
	@echo "🧹 Cleaning up containers..."
	$(COMPOSE) --profile tunnel down --remove-orphans
	docker system prune -f
	@echo "✅ Containers removed. Data volumes preserved."
	@echo "   To delete ALL data: docker volume rm life-assistant_postgres_data life-assistant_redis_data"

# Complete reset (rebuilds everything, preserves data)
reset: clean
	@echo "🔄 Complete reset..."
	$(BUILD_ENV) $(COMPOSE) --profile tunnel build --no-cache
	@echo "✅ Reset complete! Run 'make start' to restart"

# Check service health and system stats
status:
	@echo "📊 Checking system status..."
	@echo ""
	@$(COMPOSE) exec backend bundle exec rails runner scripts/status.rb 2>/dev/null || \
		(echo "⚠️  Backend not running. Starting services..." && $(COMPOSE) up -d && sleep 5 && $(COMPOSE) exec backend bundle exec rails runner scripts/status.rb)

# Production data health check - validates data integrity
# Run after deployments or when debugging production issues
health-check:
	@echo "🏥 Running production data health check..."
	@$(COMPOSE) exec backend bundle exec rails runner scripts/health_check.rb

# Check Docker container status only
status-docker:
	@echo "🐳 Docker Container Status:"
	@$(COMPOSE) ps

# Database tasks
migrate:
	$(COMPOSE) exec backend bundle exec rails db:migrate

db-prepare:
	$(COMPOSE) exec backend bundle exec rails db:prepare

# Send a magic sign-in link to a user (requires email to be configured)
# Usage: make magic-link EMAIL=user@example.com
magic-link:
	@if [ -z "$(EMAIL)" ]; then \
		echo "Usage: make magic-link EMAIL=user@example.com"; \
		exit 1; \
	fi
	@echo "📧 Sending magic sign-in link to $(EMAIL)..."
	$(COMPOSE) exec -T -e EMAIL=$(EMAIL) backend bundle exec rails runner "\
	  require 'uri'; \
	  email = ENV.fetch('EMAIL').strip.downcase; \
	  user = User.find_or_create_by!(email: email); \
	  server_url = ENV['SERVER_PUBLIC_URL'].presence || \"http://localhost:#{ENV['PORT'] || 3033}\"; \
	  server_name = ENV['SERVER_DISPLAY_NAME'].presence || (URI.parse(server_url).host rescue 'My Server'); \
	  runner = Class.new { include JwtAuth }.new; \
	  token = runner.issue_signin_token(user.email); \
	  MagicLinkMailer.with(user: user, token: token, server_url: server_url, server_name: server_name).signin.deliver_now; \
	  puts 'DELIVERED' \
	"

# Generate an invite code for a user (alternative to magic link when email not configured)
# Usage: make invite-code EMAIL=user@example.com
invite-code:
	@if [ -z "$(EMAIL)" ]; then \
		echo "Usage: make invite-code EMAIL=user@example.com"; \
		exit 1; \
	fi
	@echo "🎟️  Generating invite code for $(EMAIL)..."
	@RESULT=$$($(COMPOSE) exec -T -e EMAIL=$(EMAIL) backend bundle exec rails runner "\
	  require 'cgi'; \
	  email = ENV.fetch('EMAIL').strip.downcase; \
	  user = User.find_or_create_by!(email: email); \
	  invite = user.invite_tokens.build; \
	  code = invite.set_token!; \
	  invite.save!; \
	  scheme = ENV['APP_URL_SCHEME'].presence || 'heyhouston'; \
	  server_url = ENV['SERVER_PUBLIC_URL'].presence || \
	    (ENV['NGROK_DOMAIN'].present? ? \"https://#{ENV['NGROK_DOMAIN']}\" : \"http://localhost:#{ENV.fetch('PORT', 3033)}\"); \
	  server_name = ENV['SERVER_DISPLAY_NAME'].presence || 'Houston'; \
	  params = { url: server_url, email: email, token: code, name: server_name, type: 'invite' }.map { |k, v| \"#{k}=#{CGI.escape(v.to_s)}\" }.join('&'); \
	  invite_link = \"#{scheme}://signin?#{params}\"; \
	  puts \"TOKEN:#{code}\"; \
	  puts \"LINK:#{invite_link}\"; \
	  puts \"SERVER:#{server_url}\"; \
	" 2>/dev/null | grep -v "Sidekiq\|INFO\|pid=" | tr -d '\r'); \
	INVITE_CODE=$$(echo "$$RESULT" | grep "^TOKEN:" | cut -d: -f2-); \
	INVITE_LINK=$$(echo "$$RESULT" | grep "^LINK:" | cut -d: -f2-); \
	SERVER_URL=$$(echo "$$RESULT" | grep "^SERVER:" | cut -d: -f2-); \
	EMAIL_PROVIDER=$$(grep '^EMAIL_PROVIDER=' .env 2>/dev/null | cut -d= -f2); \
	echo ""; \
	if [ -n "$$EMAIL_PROVIDER" ]; then \
		$(COMPOSE) exec -T -e EMAIL=$(EMAIL) -e SERVER_URL="$$SERVER_URL" backend bundle exec rails runner " \
			user = User.find_by!(email: ENV['EMAIL'].strip.downcase); \
			server_url = ENV['SERVER_URL']; \
			server_name = ENV['SERVER_DISPLAY_NAME'].presence || (URI.parse(server_url).host rescue 'Houston'); \
			helper = Class.new { include JwtAuth }.new; \
			token = helper.issue_signin_token(user.email, context: 'app'); \
			MagicLinkMailer.with(user: user, token: token, server_url: server_url, server_name: server_name).app_signin.deliver_now; \
		" 2>/dev/null; \
		echo "  ┌─────────────────────────────────────────────────────┐"; \
		echo "  │  📧 Magic link sent! Check your email.              │"; \
		echo "  └─────────────────────────────────────────────────────┘"; \
		echo ""; \
		echo "  Or share this invite link (tap to sign in on iOS):"; \
		echo ""; \
		echo "  $$INVITE_LINK"; \
		echo ""; \
		echo "  ┌─────────────────────────────────────────────────────┐"; \
		echo "  │  Admin dashboard ($$SERVER_URL/admin):"; \
		echo "  │     Email:  $(EMAIL)"; \
		echo "  │     Code:   $$INVITE_CODE"; \
		echo "  └─────────────────────────────────────────────────────┘"; \
	else \
		echo "  ┌─────────────────────────────────────────────────────┐"; \
		echo "  │  📱 Invite Link (tap to sign in on iOS):            │"; \
		echo "  └─────────────────────────────────────────────────────┘"; \
		echo ""; \
		echo "  $$INVITE_LINK"; \
		echo ""; \
		echo "  Text or share this link. Tap to sign in directly."; \
		echo ""; \
		echo "  ┌─────────────────────────────────────────────────────┐"; \
		echo "  │  Admin dashboard ($$SERVER_URL/admin):"; \
		echo "  │     Email:  $(EMAIL)"; \
		echo "  │     Code:   $$INVITE_CODE"; \
		echo "  └─────────────────────────────────────────────────────┘"; \
		echo ""; \
		echo "  Code valid for 24 hours after first use."; \
	fi; \
	echo ""

# Create a demo account for Apple TestFlight review
# Generates credentials to paste into App Store Connect
demo-account:
	@echo "🍎 Creating demo account for Apple TestFlight review..."
	@SERVER_URL=$$(grep '^SERVER_PUBLIC_URL=' .env 2>/dev/null | cut -d= -f2); \
	NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env 2>/dev/null | cut -d= -f2); \
	if [ -z "$$SERVER_URL" ] && [ -n "$$NGROK_DOMAIN" ]; then \
		SERVER_URL="https://$$NGROK_DOMAIN"; \
	fi; \
	if [ -z "$$SERVER_URL" ]; then \
		echo ""; \
		echo "⚠️  No SERVER_PUBLIC_URL or NGROK_DOMAIN found in .env"; \
		echo "   Apple reviewers need a public URL to test against."; \
		echo ""; \
		echo "   Set one of these in your .env:"; \
		echo "   SERVER_PUBLIC_URL=https://your-server.com"; \
		echo "   NGROK_DOMAIN=your-subdomain.ngrok-free.app"; \
		echo ""; \
		exit 1; \
	fi; \
	DEMO_EMAIL="demo@apple-review.local"; \
	RESULT=$$($(COMPOSE) exec -T -e EMAIL="$$DEMO_EMAIL" -e SERVER_URL="$$SERVER_URL" backend bundle exec rails runner " \
		require 'cgi'; \
		email = ENV.fetch('EMAIL').strip.downcase; \
		server_url = ENV.fetch('SERVER_URL'); \
		user = User.find_or_create_by!(email: email); \
		user.invite_tokens.destroy_all; \
		invite = user.invite_tokens.build; \
		code = invite.set_token!; \
		invite.save!; \
		invite_link = \"heyhouston://signin?url=#{CGI.escape(server_url)}&email=#{CGI.escape(email)}&token=#{CGI.escape(code)}&name=Houston&type=invite\"; \
		puts \"CODE:#{code}\"; \
		puts \"LINK:#{invite_link}\"; \
	" 2>/dev/null | grep -v "Sidekiq\|INFO\|pid=" | tr -d '\r'); \
	INVITE_CODE=$$(echo "$$RESULT" | grep "^CODE:" | cut -d: -f2-); \
	INVITE_LINK=$$(echo "$$RESULT" | grep "^LINK:" | cut -d: -f2-); \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "  ✅ Demo account ready for Apple TestFlight review"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo ""; \
	echo "  Copy these into App Store Connect → App Review Information:"; \
	echo ""; \
	echo "  ┌─────────────────────────────────────────────────────────┐"; \
	echo "  │  Sign-in required:  Yes                                 │"; \
	echo "  │  Demo Account:      $$DEMO_EMAIL"; \
	echo "  │  Password:          (paste the invite link below)       │"; \
	echo "  └─────────────────────────────────────────────────────────┘"; \
	echo ""; \
	echo "  ┌─────────────────────────────────────────────────────────┐"; \
	echo "  │  Invite Link (paste as password AND in review notes):   │"; \
	echo "  └─────────────────────────────────────────────────────────┘"; \
	echo ""; \
	echo "  $$INVITE_LINK"; \
	echo ""; \
	echo "  ┌─────────────────────────────────────────────────────────┐"; \
	echo "  │  Review Notes (paste this):                             │"; \
	echo "  └─────────────────────────────────────────────────────────┘"; \
	echo ""; \
	echo "  Houston is a self-hosted AI assistant app."; \
	echo "  "; \
	echo "  TO SIGN IN:"; \
	echo "  1. Open the Houston app"; \
	echo "  2. Tap the rainbow-colored \"use server invite code\" text"; \
	echo "  3. In the \"Paste invite link\" field, paste this link:"; \
	echo "  "; \
	echo "  $$INVITE_LINK"; \
	echo "  "; \
	echo "  4. Tap \"Sign In\""; \
	echo ""; \
	echo "  The invite code is valid for 24 hours after first use."; \
	echo "  Server: $$SERVER_URL"; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo ""

# Interactive wizard to add a local stdio MCP (mcp_servers.json)
add-mcp:
	./scripts/mcp_wizard.sh

# Shortcut: import JSON path preselected
add-mcp-json:
	CHOICE=1 ./scripts/mcp_wizard.sh

# Show MCP servers via Rails runner (bypasses HTTP auth)
mcp-status:
	$(COMPOSE) run --rm backend bundle exec rails runner "puts JSON.pretty_generate(Mcp::ConnectionManager.instance.list_servers)"

# Force reload/probe and show servers
mcp-probe:
	$(COMPOSE) run --rm backend bundle exec rails runner "m=Mcp::ConnectionManager.instance; m.send(:reload!); puts JSON.pretty_generate(m.list_servers)"

# iOS Development Commands
ios-check:
	@echo "🍎 Validating iOS code compilation..."
	@chmod +x scripts/ios_build_check.sh
	@./scripts/ios_build_check.sh

ios-check-clean:
	@echo "🍎 Clean build + iOS compilation validation..."
	@chmod +x scripts/ios_build_check.sh
	@./scripts/ios_build_check.sh --clean

ios-check-verbose:
	@echo "🍎 Validating iOS code compilation (verbose)..."
	@chmod +x scripts/ios_build_check.sh
	@./scripts/ios_build_check.sh --verbose

ios-build-device:
	@echo "📱 Building and deploying to device..."
	@chmod +x scripts/ios_build_device.sh
	@./scripts/ios_build_device.sh

ios-build-device-clean:
	@echo "📱 Clean build + deploy to device..."
	@chmod +x scripts/ios_build_device.sh
	@./scripts/ios_build_device.sh --clean

ios-build-device-verbose:
	@echo "📱 Building and deploying to device (verbose)..."
	@chmod +x scripts/ios_build_device.sh
	@./scripts/ios_build_device.sh --verbose

ios-beta:
	@echo "🚀 Building and uploading to TestFlight..."
	@chmod +x ios/scripts/testflight.sh
	@ios/scripts/testflight.sh $(if $(DRY),--dry-run)

ios-beta-dry:
	@echo "🔍 TestFlight deployment preview (dry run)..."
	@chmod +x ios/scripts/testflight.sh
	@ios/scripts/testflight.sh --dry-run
