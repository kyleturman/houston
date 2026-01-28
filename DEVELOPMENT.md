# Development Guide

This guide covers development setup, iOS app building, testing, deployment, and troubleshooting.

## Prerequisites

- Docker Desktop (or Colima + Docker Compose)
- For iOS: Xcode 15+, XcodeGen (`brew install xcodegen`)

## Development Workflow

### Starting the Server

```bash
make dev       # Foreground with logs (recommended for development)
make start     # Background daemon (auto-restarts after reboot)
make stop      # Stop all services
make restart   # Restart all services
```

### Viewing Logs

```bash
make logs          # All services
make logs-rails    # Rails backend only
```

### Rails Console

```bash
make shell         # Opens Rails console
```

### Running Commands in Docker

All Rails commands must run inside Docker:

```bash
# Pattern: docker-compose exec backend bundle exec [command]
docker-compose exec backend bundle exec rails console
docker-compose exec backend bundle exec rails db:migrate
docker-compose exec -e RAILS_ENV=test backend bundle exec rspec
```

---

## iOS Development

### Setup

1. Start the backend server (see above)
2. Generate Xcode project:
   ```bash
   brew install xcodegen    # If not installed
   cd ios && xcodegen generate
   open Houston.xcodeproj
   ```

3. Connect to your server via magic link email

### Build Commands

```bash
make ios-check           # Validate compilation
make ios-build-device    # Build and deploy to connected device
make ios-beta            # Build and upload to TestFlight
```

### Magic Link Authentication

The iOS app uses magic links for authentication:

1. Run `make start` - on first run, you'll be prompted to enter your email
2. Run `make magic-link EMAIL=you@example.com` to get a sign-in link
3. Tap the link on your iPhone to open the app and authenticate

To send a new magic link:
```bash
make magic-link EMAIL=user@example.com
```

### Environment Variables for iOS

| Variable | Description |
|----------|-------------|
| `SERVER_PUBLIC_URL` | URL the iOS app uses to connect (e.g., ngrok domain) |
| `PAIRING_JWT_SECRET` | Secret for signing auth tokens |
| `SIGNIN_TOKEN_TTL` | Magic link expiry in seconds (default: 900) |

### TestFlight Distribution

Automated TestFlight uploads are handled via Fastlane.

#### One-Time Setup

1. **Install dependencies:**
   ```bash
   cd ios/fastlane
   bundle install
   ```

2. **Create App Store Connect API Key:**
   - Go to [App Store Connect → Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api)
   - Click "+" to generate a new key with "App Manager" role
   - Download the `.p8` file (only downloadable once!)
   - Note the Key ID and Issuer ID

3. **Configure secrets:**
   ```bash
   cd ios/fastlane
   cp .env.example .env
   ```

   Edit `.env`:
   ```bash
   APPLE_TEAM_ID=YOUR_TEAM_ID          # From developer.apple.com/account
   ASC_KEY_ID=YOUR_KEY_ID              # From step 2
   ASC_ISSUER_ID=YOUR_ISSUER_ID        # From step 2
   ```

   Move the `.p8` file to `ios/fastlane/AuthKey.p8`

4. **Create External Testers group:**
   - App Store Connect → Your App → TestFlight
   - Under "External Testing", click "+" to create "External Testers" group
   - Enable "Public Link" to get a shareable URL

#### Building & Uploading

```bash
make ios-beta                              # Build and upload
CHANGELOG="New features" make ios-beta     # With release notes
make ios-beta-upload                       # Upload existing build
```

#### Public TestFlight Link

Once configured, your public link will be:
```
https://testflight.apple.com/join/XXXXXXXX
```

Anyone with this link can join your beta (up to 10,000 testers).

#### Apple Review Requirements

External TestFlight requires Apple review. **This is handled automatically** by `make ios-beta`:

1. Creates a `demo@apple-review.local` user with fresh invite code
2. Sets the demo account credentials via App Store Connect API
3. Adds review notes explaining how to sign in

No manual steps required - just run `make ios-beta` and the review info is submitted automatically.

To generate credentials manually (for reference):
```bash
make demo-account
```

---

## Testing

### Quick Tests (Mocked, Free)

```bash
make test          # All tests
make test-smoke    # Critical path only (~1s)
```

### Real LLM Tests (Cost Money)

```bash
make test-llm-provider     # Connectivity check (~$0.001)
make test-llm-goal         # Goal agent workflow (~$0.03)
make test-llm-create-goal  # Goal creation (~$0.02-0.05)
```

### Running Specific Tests

```bash
make test-file FILE=spec/models/goal_spec.rb
```

---

## Database

### Migrations

```bash
make migrate      # Run pending migrations
make db-prepare   # Create DB + run migrations (idempotent)
```

### Direct Access

```bash
# Rails console
make shell

# PostgreSQL
docker-compose exec postgres psql -U houston -d houston_development
```

---

## LLM Configuration

### Supported Providers

**Cloud (API Key Required)**
```bash
# Anthropic Claude (recommended)
ANTHROPIC_API_KEY=sk-ant-...
LLM_AGENTS_MODEL=anthropic:sonnet-4.5
LLM_TASKS_MODEL=anthropic:haiku-4.5

# OpenAI
OPENAI_API_KEY=sk-...
LLM_AGENTS_MODEL=openai:gpt-4.1

# OpenRouter (400+ models)
OPENROUTER_API_KEY=sk-or-...
LLM_AGENTS_MODEL=openrouter:meta-llama/llama-3.3-70b-instruct
```

**Local (Free, Private)**
```bash
# Install Ollama
brew install ollama && brew services start ollama
ollama pull qwen3:14b

# Configure
LLM_AGENTS_MODEL=ollama:qwen3:14b
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

### Model Selection

| Use Case | Recommended Model | Why |
|----------|------------------|-----|
| Agents (complex reasoning) | `anthropic:sonnet-4.5` | Best tool use |
| Tasks (simple operations) | `anthropic:haiku-4.5` | Fast, cheap |
| Local/Private | `ollama:qwen3:14b` | Good tool calling |

---

## Deployment

### Home Server / Mac Mini

```bash
make init
make start    # Runs in background, auto-restarts
```

Add ngrok for remote access:
```bash
# In .env
NGROK_AUTHTOKEN=your_token
NGROK_DOMAIN=houston-you.ngrok-free.app

make restart  # ngrok starts automatically
```

### VPS (DigitalOcean, Hetzner, etc.)

```bash
git clone https://github.com/yourusername/houston.git && cd houston
make init

# Edit .env
RAILS_ENV=production
POSTGRES_PASSWORD=$(openssl rand -hex 32)
SERVER_PUBLIC_URL=https://your-domain.com

make start
```

### Heroku

```bash
heroku create your-app-name
heroku config:set SECRET_KEY_BASE=$(openssl rand -hex 64)
heroku config:set ANTHROPIC_API_KEY=sk-ant-...
git push heroku main
```

---

## Troubleshooting

### Services Not Starting

```bash
make logs              # Check for errors
make restart           # Restart everything
docker-compose ps      # Check container status
```

### Port Conflict

```bash
# Change port in .env
PORT=3034
make restart
```

### Database Issues

```bash
make db-prepare        # Reset and migrate
make migrate           # Just run migrations
```

### LLM Errors

```bash
# Verify API key
grep "API_KEY" .env

# Test connectivity
make test-llm-provider
```

### iOS Can't Connect

1. Ensure server is running: `make status`
2. If using ngrok, check it's running: `docker-compose ps`
3. Verify `SERVER_PUBLIC_URL` in `.env` matches your ngrok domain
4. Send a new magic link: `make magic-link EMAIL=you@example.com`

### Complete Reset

```bash
make clean             # Remove containers (keeps data)
make reset             # Full rebuild
```

To delete all data:
```bash
docker volume rm life-assistant_postgres_data life-assistant_redis_data
make start
```

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Run tests: `make test-smoke`
4. Commit changes: `git commit -m 'Add amazing feature'`
5. Push: `git push origin feature/amazing-feature`
6. Open a Pull Request

### Code Style

- Follow existing patterns in the codebase
- Run `make test-smoke` before committing
- For iOS changes, run `make ios-check`

---

## System Requirements

**Minimum:**
- 2GB RAM, 2 CPU cores, 10GB disk

**Recommended:**
- 4GB RAM, 4 CPU cores, 50GB disk

---

## Additional Resources

- [Agent System Documentation](backend/app/services/agents/README.md)
- [Security Model](SECURITY.md)
- [Backend Development](backend/CLAUDE.md)
- [iOS Development](ios/CLAUDE.md)
