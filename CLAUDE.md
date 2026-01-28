# Houston - AI Agent Development Guide
- Houston is an open-source iOS + Rails app running in a docker container that uses AI agents to help users achieve goals
- It is self-hosted by users, averaging around 1-20 users per instance

---

## ⚠️ STOP - READ PLATFORM GUIDE BEFORE ANY TASK

**You MUST use your file read tool on the platform-specific guide BEFORE writing any code:**

| Working on... | READ THIS FILE NOW (use file read tool) |
|---------------|----------------------------------------|
| Backend (Rails, agents, LLM, tools) | `./backend/CLAUDE.md` |
| iOS (Swift, UI, views) | `./ios/CLAUDE.md` |
| Both | Read BOTH files above |
| Agents, LLMs, orchestrator | Also read: `./backend/app/services/agents/README.md` |

**This is NOT optional.** These guides contain critical patterns, gotchas, and conventions that will cause bugs if ignored.

---

## ⚡ Pre-Commit Checklist

```bash
make test-smoke          # <10s, ALWAYS run before commit
make ios-check           # iOS only - validates compilation
make test-llm-goal       # After agent/orchestrator changes (~$0.03)
make health-check        # After migrations, data imports, or when debugging data issues
```

IMPORTANT: Check the makefile if a command already exists before trying to run it yourself.

---

## 🛠️ Commands

### Development
```bash
make dev              # Start (foreground)
make start            # Start (background)
make stop             # Stop services
make logs-rails       # Watch logs
```

### Database
```bash
make shell            # Rails console (dev)
make migrate          # Run migrations
```

### Testing
```bash
make test             # All tests (~2s)
make test-smoke       # Critical path (~1s)
```

### Running Ruby Commands

**NEVER run commands directly:**
```bash
# ❌ WRONG - These will FAIL
rails console
bundle exec rspec
rails db:migrate
```

**ALWAYS use docker-compose exec:**
```bash
# ✅ CORRECT
docker-compose exec backend bundle exec rails console
docker-compose exec -e RAILS_ENV=test backend bundle exec rails console
docker-compose exec backend bundle exec rails db:migrate
docker-compose exec -e RAILS_ENV=test backend bundle exec rspec spec/models/
```

**Pattern:** `docker-compose exec [-e RAILS_ENV=test] backend bundle exec [COMMAND]`

---

## 📁 Key File Locations

```bash
# Backend
backend/app/models/concerns/agentable.rb              # Core agent logic
backend/app/services/agents/**/*.rb                   # Agent system
backend/app/services/llms/prompts/**/*.rb             # All prompts
backend/app/services/tools/system/**/*.rb             # System tools

# iOS
ios/Sources/Core/Data/**/*.swift                      # APIClient, models
ios/Sources/Core/Networking/**/*.swift                # SSE, StateManager
ios/Sources/Core/ViewModels/**/*.swift                # ViewModels
ios/Sources/Features/**/*.swift                       # Feature code
```

**Deep dive:** `backend/app/services/agents/README.md` (comprehensive agent system guide)

---

## Important general coding rules
- Follow DRY, KISS, and YAGNI coding principles to keep code clean, modular, and maintainable
- Consider code you're working on holistically with the code it touches
- When in doubt, follow the code trace to understand the context
- Leave comments to help yourself and future developers understand the code
- DO NOT comment on if something is changed, but rather keep comments about what the code does and why
- Test code changes locally before committing

## Next Steps

1. **Read the platform-specific guide** for detailed patterns and gotchas
2. **Use Glob to explore** the codebase structure
3. **Run pre-commit checks** before committing
4. **Follow DRY principles** - keep it simple
