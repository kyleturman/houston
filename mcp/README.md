# MCP Configuration

This directory contains configuration for MCP (Model Context Protocol) servers.

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐
│  iOS App        │     │  Backend        │
│  (auth UI)      │────▶│  (token store)  │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
           ┌───────────────┐         ┌───────────────┐
           │ Local Servers │         │ Remote Servers│
           │ (stdio/Docker)│         │ (HTTP/SSE)    │
           └───────────────┘         └───────────────┘
```

**Local servers** run as subprocesses (Docker containers or npx commands). The backend spawns them and passes credentials via environment variables.

**Remote servers** are HTTP endpoints hosted elsewhere. The app handles OAuth directly with the remote server.

## Files

| File | Purpose |
|------|---------|
| `servers.json` | Local server definitions |
| `default_remote_servers.json` | Pre-configured remote servers shipped with the app |
| `auth-providers/*.json` | OAuth/auth configurations for local servers |
| `credentials/` | OAuth credential files like `google.json` (gitignored) |

## Credentials

Credentials live in **Root `.env` file** - API keys and OAuth client secrets:
   ```
   BRAVE_API_KEY=xxx
   PLAID_CLIENT_ID=xxx
   PLAID_SECRET=xxx
   TODOIST_CLIENT_ID=xxx
   TODOIST_CLIENT_SECRET=xxx
   ```

The auth provider configs reference these via `credentialsEnv` (for env vars).

## Auth Types

| Type | Use Case | Flow |
|------|----------|------|
| `none` | API key in env var | Backend passes env var to server |
| `oauth2` | Standard OAuth (Google, Todoist) | iOS handles OAuth, backend stores tokens, passes to server |
| `plaid_link` | Plaid's Link SDK | iOS uses Plaid SDK, backend stores access tokens |
| `oauth_consent` | Remote MCP servers | iOS does OAuth directly with remote server via `.well-known` discovery |
| `api_key` | Remote servers with API keys | User enters key in app, stored and sent with requests |

## Connection Strategies

- **`single`** (default): One connection per user (e.g., one Google Calendar account)
- **`multiple`**: Multiple connections allowed (e.g., multiple bank accounts via Plaid)

---

## Adding a Remote MCP Server

Remote servers are the simplest to add. They handle their own auth via OAuth 2.1.

Add to `default_remote_servers.json`:

```json
{
  "servers": {
    "example": {
      "enabled": true,
      "name": "Example Service",
      "description": "What this server does",
      "url": "https://mcp.example.com/mcp",
      "auth_type": "oauth_consent"
    }
  }
}
```

**Requirements:**
- URL must be the MCP endpoint (typically `/mcp`, not `/sse`)
- Server must support OAuth 2.1 with `.well-known/oauth-authorization-server` discovery
- After adding, restart services: `make restart`

---

## Adding a Local MCP Server

Local servers run as subprocesses. They're more complex but give you full control.

### Option 1: Use an existing MCP server package

Add to `servers.json`:

```json
{
  "servers": {
    "todoist": {
      "name": "Todoist",
      "description": "Task management",
      "transport": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-todoist"],
      "authProvider": "auth-providers/todoist-oauth.json",
      "authScope": "default",
      "connectionStrategy": "single"
    }
  }
}
```

### Option 2: Run via Docker

```json
{
  "servers": {
    "brave-search": {
      "name": "Brave Search",
      "description": "Web search",
      "transport": "stdio",
      "command": "docker",
      "args": ["run", "-i", "--rm", "-e", "BRAVE_API_KEY", "mcp/brave-search"],
      "env": {
        "BRAVE_API_KEY": "${BRAVE_API_KEY}"
      },
      "authProvider": "auth-providers/none.json",
      "connectionStrategy": "single"
    }
  }
}
```

### Server Config Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name in the app |
| `description` | Yes | Brief description |
| `transport` | Yes | `stdio` for local servers |
| `command` | Yes | Command to run (`npx`, `docker`, etc.) |
| `args` | Yes | Command arguments |
| `authProvider` | Yes | Path to auth provider config |
| `authScope` | No | Which scope to use from the auth provider |
| `connectionStrategy` | No | `single` (default) or `multiple` |
| `env` | No | Environment variables to pass |
| `tokenPath` | No | Where the MCP server expects token file (for servers that read tokens from disk) |
| `tokenFormat` | No | Template for token file format |

---

## Creating an Auth Provider

Auth providers define how to authenticate users for local servers.

### For OAuth 2.0 services

Create `auth-providers/myservice-oauth.json`:

```json
{
  "type": "oauth2",
  "displayName": "MyService Account",
  "description": "Sign in with MyService",

  "backend": {
    "authorizeEndpoint": {
      "url": "https://myservice.com/oauth/authorize",
      "params": {
        "client_id": "{{client_id}}",
        "redirect_uri": "{{redirect_uri}}",
        "response_type": "code",
        "scope": "{{scope}}",
        "state": "{{state}}"
      }
    },
    "tokenEndpoint": {
      "url": "https://myservice.com/oauth/token",
      "method": "POST",
      "headers": {
        "Content-Type": "application/x-www-form-urlencoded"
      },
      "body": {
        "client_id": "{{client_id}}",
        "client_secret": "{{client_secret}}",
        "code": "{{code}}",
        "redirect_uri": "{{redirect_uri}}",
        "grant_type": "authorization_code"
      },
      "response": {
        "accessToken": "access_token",
        "refreshToken": "refresh_token",
        "expiresIn": "expires_in"
      }
    },
    "credentialsEnv": ["MYSERVICE_CLIENT_ID", "MYSERVICE_CLIENT_SECRET"]
  },

  "scopes": {
    "default": "read write"
  },

  "runtime": {
    "envMapping": {
      "accessToken": "MYSERVICE_ACCESS_TOKEN"
    }
  },

  "ios": {
    "handler": "oauth2",
    "pkceEnabled": true,
    "redirectUri": "heyhouston://oauth-callback"
  }
}
```

**Key sections:**
- `backend`: How the backend exchanges auth codes for tokens
- `scopes`: Named scope sets (referenced by `authScope` in server config)
- `runtime.envMapping`: How tokens are passed to the MCP server process
- `ios`: iOS-specific OAuth handling config

### For services with no auth (API key in env)

Use the existing `auth-providers/none.json`:

```json
{
  "type": "none",
  "displayName": "No Authentication",
  "description": "This service does not require authentication"
}
```

Then pass the API key via `env` in your server config.

---

## Building Your Own MCP Server

If you're building a custom MCP server (like `plaid-server/`):

1. **Create a stdio-based MCP server** that reads credentials from environment variables
2. **Containerize it** with a Dockerfile
3. **Add to `servers.json`** with appropriate auth provider
4. **Build the image**: `docker build -t mcp/myserver ./mcp/myserver`

The backend will:
1. Spawn your container with `-i` (interactive stdin)
2. Pass user tokens via environment variables (per `runtime.envMapping`)
3. Communicate via MCP protocol over stdio

See `plaid-server/` for a complete example.

---

## Token Flow for Local Servers

```
1. User taps "Connect" in iOS app
2. iOS opens OAuth flow (in-app browser)
3. User authorizes, redirected back to app
4. iOS sends auth code to backend
5. Backend exchanges code for tokens (via auth provider config)
6. Backend stores tokens in database (UserMcpConnection)
7. When MCP server is needed:
   a. Backend retrieves user's tokens
   b. Spawns server process with tokens in env vars
   c. Server uses tokens to call external APIs
```

---

## Troubleshooting

**Server not appearing in app?**
- Check `servers.json` syntax
- Ensure auth provider file exists
- Restart backend: `make restart`

**OAuth failing?**
- Verify credentials are set in root `.env` file (or `mcp/credentials/` for file-based creds)
- Check redirect URI matches OAuth app config
- Look at backend logs for token exchange errors

**Server timing out?**
- Check Docker image builds successfully
- Verify command/args are correct
- Test manually: `docker run -i --rm mcp/myserver`
