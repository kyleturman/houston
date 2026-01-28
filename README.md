# 🛰️  Houston

A self-hosted AI life assistant on the ground to help you achieve your goals. Set goals, track progress with notes, and let autonomous agents help you stay on track — all while keeping your data private on your own server.

> **⚠️ Experimental Project:** This is a personal project I built for my own use and decided to open-source for others to use and learn from. It's not guaranteed to work, may have rough edges, won't be guaranteed to continue to be updated, and could break at any time. It's designed to be as private and secure as possible but may have gaps. Feel free to fork, make your own, and use at your own risk!

## What is Houston?

Houston consists of two parts:

1. **Server** - Runs on your computer, home server, or VPS. Manages your data, runs AI agents, and syncs with your phone.

2. **iOS App** - Native iPhone app for daily use. Set goals, add notes, chat with agents, and browse your discovery feed.

### 📲 Once you are done setting up your server: **[➡️ Download the App from TestFlight Beta ⬅️](https://testflight.apple.com/join/jHW5NtU3)**
You can also build the app yourself using the code here if you'd rather do that, but this is much faster.

## Key features

Houston is built around **goal-oriented AI agents** that work autonomously on your behalf. Here's what's under the hood:

### 🔁 The Agent Loop

At the core is a **ReAct (Reasoning + Acting) loop**: the AI thinks, calls tools, observes results, and repeats until the task is done. Each iteration streams responses in real-time via Server-Sent Events, so you see the agent's work as it happens. Safety limits (max 20 iterations, 10-minute timeout, loop detection) prevent runaway execution. The system batches tool calls (max 2 per turn) to keep costs predictable.

### 🎯 Goals & Goal Agents

Goals are the central organizing unit. When you create a goal you use a **guided chat** where the AI helps you articulate what you want to achieve, what success looks like, and relevant constraints. Each goal gets its own agent with custom instructions and accumulated knowledge through notes and learnings. Goal agents are conversational—they respond when you message them and can proactively check in on schedules you set.

### 📅 Check-Ins

Goals support two types of proactive engagement:
- **Scheduled check-ins**: Recurring daily, weekdays, or weekly at times you choose
- **Follow-up check-ins**: One-time reminders the agent sets contextually ("I'll check back in 3 days")

When a check-in fires, the agent reviews recent notes, considers the original intent, and decides whether to create tasks, update learnings, or just reschedule.

### 📚 Learnings

Learnings are the agent's **persistent memory**—short, durable facts that survive across conversations. Things like "prefers morning check-ins" or "budget is $500/month" are stored as learnings rather than in conversation history. Agents can add, update, or remove learnings as they discover new information. Each goal maintains its own learnings, plus there's a global user-level memory that users can explicitly direct the agent to use across goals.

### 📝 Notes

Notes are how you and your agents capture knowledge. You can jot down observations, save links, or record research findings—all tied to a specific goal. Notes added at a top level can even automatically detect which goal they belong to. Agents create notes too when they complete tasks or discover relevant information. Recent notes are included in the agent's context, and searchable by the agent, with user notes weighted higher than agent notes.

### 🌐 Web Parsing

When you save a URL (via the app or share sheet), the system automatically enriches it:
1. **Immediate**: Extracts metadata (title, description, Open Graph images)
2. **Background**: Fetches full content using a headless browser, generates an AI summary, and extracts structured data (recipes, products, articles)
3. **YouTube**: Fetches the full video transcript so agents can reference specific content

This turns link-saving into knowledge capture—you get searchable, summarized content without manual effort.

### 📝 Tasks

When work requires research or external information, agents spawn **autonomous tasks**. Tasks run independently in the background: they search the web, gather information, and create a note with their findings. This "delegate and forget" pattern lets your goal agent continue chatting while research happens in parallel and can use a less sophisticated and more affordable model. Tasks auto-complete after creating their output and have built-in retry logic for failures.

### 📜 Session History

Conversations have **unlimited context** through automatic archival. When a session grows long or goes stale (12+ messages or 24+ hours), the system archives it with an AI-generated summary. Future conversations include these summaries, so the agent remembers past discussions without loading the full history. You can also browse previous sessions in the UI.

### 📡 Discovery Feed

Three times daily (morning, afternoon, evening and customizable by the user), the system generates a personalized feed by analyzing your active goals. It creates:
- **Discoveries**: Curated links to articles, videos, and resources relevant to your goals
- **Reflections**: Thoughtful prompts to capture progress or consider new angles

The feed prioritizes community content over SEO-optimized articles, tracks what you've seen to avoid repetition, and includes occasional serendipitous finds adjacent to your goals.

### 🔌 MCP Integrations

Houston connects to external services via the **Model Context Protocol (MCP)**. Each integration (Gmail, Google Calendar, Plaid, etc.) runs as a separate server—either as a Docker container or HTTP endpoint. When an agent needs to check your calendar or search emails, it calls the appropriate MCP tool. OAuth tokens and API keys are stored encrypted, and multi-account support lets you connect multiple accounts. Gmail, Google Calendar, and Plaid are all custom-made MCP servers included in the repository to ensure security and flexibility.

### ⤴️ Share Sheet

The iOS app includes a share extension so you can save content from anywhere. Tap share in Safari, Notes, or any app, select "Save to Houston," optionally pick a goal, and the URL/text becomes a note. The extension uses an App Group to share authentication with the main app, so no separate login is needed.

## Example use case

Here's how the pieces fit together. Say you want to learn to play piano:

**Creating the goal** — You start a new goal and chat with the AI. It asks what draws you to piano, whether you have access to one, your time constraints, and what success looks like. From this conversation, it creates a goal with tailored instructions ("focus on practical skills over theory, user has 30 min/day") and initial learnings ("has digital keyboard at home", "prefers morning practice").

**First steps** — The agent creates an initial task to research beginner approaches. The task runs in the background, searches for current recommendations, and produces a note summarizing options (apps like Simply Piano, YouTube channels, method books). The agent messages you with a suggested starting point.

**Adding notes** — You find a YouTube tutorial you like and share it to Houston. The system fetches the video transcript and generates a summary. Later you jot down "struggled with left hand coordination today"—the agent sees this in your next conversation and can reference it.

**Check-ins** — You tell the agent to set up weekday check-ins at 9am. Each morning, the agent reviews your recent notes, asks how practice is going, and adjusts its advice. After a week it notices you've mentioned hand coordination twice, saves a learning ("working on left hand independence"), and creates a task to find exercises specifically for that.

**Learnings accumulate** — Over time the agent builds up context: "prefers jazz standards over classical", "practicing Autumn Leaves", "finds Synthesia videos helpful". These persist across conversations so you never have to re-explain your situation.

**Discovery feed** — Each morning your feed includes a mix: maybe a Reddit thread about beginner plateaus, a new tutorial from a channel you've saved before, and a reflection prompt like "You've been at this for 3 weeks—worth recording a quick video to hear your progress?"

**MCP integrations** — If you've connected Google Calendar, the agent can check your schedule before suggesting practice times or notice you have a busy week coming up.

Houston helps you stay on track and think of things you might forget to think of, becoming a living workspace wheryour agent learns alongside you, does research you'd otherwise forget to do, and keeps you engaged without requiring you to remember where you left off.

## Minimum requirements

To run Houston locally, you'll need:

- **Docker** - [Docker Desktop](https://docker.com/products/docker-desktop) (Mac/Windows) or Docker + Compose (Linux) (2GB RAM minimum, 4GB recommended)
- **LLM API Keys or local LLM** - Anthropic, OpenAI, OpenRouter, or Ollama for AI agents. Anthropic Claude recommended.
- **Brave API Key** - Web search is required for goal agents to function. Get a free key at [brave.com/search/api](https://brave.com/search/api)
- Optional: API keys for Google Calendar, Gmail, Plaid, etc. Instructions on how to obtail in your .env file.

I run this on my Mac Mini at home which also gives a ton of flexibility to use custom MCPs and more across your local machine. You could also run this on a dedicated VPS such as DigitalOcean or Linode.


## Quick Start

```bash
git clone https://github.com/yourusername/houston.git
cd houston
make init      # Creates .env and generates all secrets
```

Edit `.env` and add your API keys (Step 1 in the file):

```bash
ANTHROPIC_API_KEY=sk-ant-...    # Or OPENAI_API_KEY, or OPENROUTER_API_KEY
BRAVE_API_KEY=BSA...            # Free at brave.com/search/api
```

Start the server:

```bash
make start     # Starts all services, prompts for admin email on first run
```

On first run, you'll be prompted to enter your email. An invite code will be generated that you can use to sign in from the iOS app.

## Configuration

The `.env` file is organized into steps. Configure based on your needs:

### Step 1: AI Configuration (Required)

Houston needs two things to work:

1. **LLM Provider** - The AI brain. Add one of:
   - `ANTHROPIC_API_KEY` (recommended)
   - `OPENAI_API_KEY`
   - `OPENROUTER_API_KEY`
   - Or use local models via Ollama

2. **Web Search** - Agents use this to research and verify information:
   - `BRAVE_API_KEY` - Get a free key at [brave.com/search/api](https://brave.com/search/api)

### Step 2: Email magic links (Optional)

To enable magic link sign-in via email, configure SMTP. See `.env` for Gmail, Resend, and Amazon SES examples. With this you can re-send sign-in links from the dashboard or through the cli with (`make magic-link EMAIL=name@example.com`).

Without email, you use invite codes to sign in (`make invite-code EMAIL=name@example.com`).

### Step 3: Remote Access (Optional)

By default, the iOS app only works on your local WiFi. To use it from anywhere:

**If you have a VPS or cloud server:**
Ideally it should pick up docker and run it as a service.
```bash
SERVER_PUBLIC_URL=https://houston.yourdomain.com
```

**If running on a home server:**
You'll need to run the server and then create a tunnel to outside internet with ngrok. The ngrok tunnel will start automatically with `make start` if you have ngrok configured.
1. Sign up at [ngrok.com](https://ngrok.com) (free)
2. Reserve a static domain in your dashboard
3. Add to `.env`:
```bash
NGROK_AUTHTOKEN=your_token
NGROK_DOMAIN=your-subdomain.ngrok-free.app
```

### Step 4: Integrations (Optional)

Expand agent capabilities by connecting external services via MCP (Model Context Protocol) or building your own. Each server needs to be configured with your own API keys. See `.env` Step 4 for API key setup, then OAuth services are connected in the ios app for configured servers.

## Commands

```bash
make start     # Start all services in production (background, auto-restarts)
make stop      # Stop all services
make dev       # Start with logs in foreground in development
make logs      # View logs
make status    # Check system health
make shell     # Open Rails console
make add-mcp   # Add MCP integration
make help      # Show all commands
```

### Adding Users

You can have multiple users on a Houston app, but it's up to you to manage costs and deployment reliability. You can add a new user from the admin dashboard or via the CLI:
```bash
make invite-code EMAIL=user@example.com  # Generate a copy-and-paste code
make magic-link EMAIL=user@example.com   # Generate a sign-in URL sent directly to their email (only works if SMTP is configured)
```

**Invite codes** are codes that users enter in the iOS app. Good for sharing directly via text.

**Magic links** are URLs that sign in automatically when clicked. Requires email to be configured (Step 3) to send via email, but the command also prints the URL for manual sharing.

## Admin Dashboard

Access the web dashboard at your server URL (e.g., `http://localhost:3033` or your public URL). The dashboard shows:

- **Cost tracking** - Lifetime spend, current month, and predicted monthly average
- **Activity graph** - API calls over time with cost breakdown
- **User management** - Invite users, send sign-in links, revoke devices
- **Service health** - Backend, database, and background job status
- **LLM configuration** - Which models are active and their API key status
- **MCP servers** - Connected integrations and their health

## Expected Cost

Houston uses LLM APIs which charge per token. With typical usage (a few active goals, daily check-ins), expect around **$10/month** in API costs when using Anthropic models. This varies based on:

- How many goals you're tracking
- How often agents run research and analysis
- Which models you configure (Claude Sonnet vs Haiku vs Opus)

The admin dashboard tracks your costs in real-time so there are no surprises.

## Architecture

| Component | Technology |
|-----------|------------|
| Backend | Ruby on Rails, PostgreSQL, Redis, Sidekiq |
| AI | Anthropic Claude, OpenAI, or Ollama (local) |
| Mobile | Native iOS (SwiftUI) |
| Deployment | Docker Compose |

## Documentation

- [Security Model](SECURITY.md) - Encryption, authentication, threat model
- [Development Guide](DEVELOPMENT.md) - Testing, iOS builds, deployment options
- [Agent System](backend/app/services/agents/README.md) - How AI agents work
- [MCP Configuration](mcp/README.md) - Adding and configuring MCP servers
- [Tools System](backend/app/services/tools/README.md) - Adding custom agent tools

## Development

Houston is designed to be forked and customized. The codebase is split into two main parts:

- **Backend** (Ruby on Rails) — Add new tools, customize agent prompts, build your own MCP servers, or modify how goals and tasks work
- **iOS App** (SwiftUI) — Customize the UI, add new screens, or adjust how features behave on mobile

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup instructions, testing, and build guides for both platforms.

## Contributing

This is primarily a personal project, so contributions are limited:

- **Bug fixes** - Welcome, but ideally they don't include breaking changes
- **New features** - Probably not accepting these, but feel free to fork

If you do submit a bug fix PR, please run `make test` to ensure tests pass successfully and the app builds correctly.

## License

MIT License - see [LICENSE](LICENSE)
