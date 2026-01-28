# Security Model

Houston is a self-hosted AI-powered personal assistant that helps you manage goals, notes, tasks, and more. This document explains how Houston protects your data and what our security model guarantees (and doesn't guarantee).

**Note: Houston is designed for self-hosting.** You control the server, the data, and the encryption keys. This gives you full ownership of your data but also means security depends on how you configure and maintain your deployment.

## Executive Summary

- ✅ **Encryption in transit**: TLS 1.3 for all communication
- ✅ **Encryption at rest (server)**: AES-256-GCM for sensitive database fields
- ✅ **Encryption at rest (iOS)**: AES-256-GCM for local cache
- ✅ **Device protection**: iOS Keychain for encryption keys
- ❌ **NOT end-to-end encrypted**: Server can decrypt data to enable AI features

## Data Encryption

### In Transit (Network)

All communication between the iOS app and server uses **TLS 1.3** with strong cipher suites:
- Client → Server: HTTPS
- Server → Client: HTTPS
- Server-Sent Events: HTTPS

**What this protects against:**
- ✅ Network eavesdropping
- ✅ Man-in-the-middle attacks
- ✅ Packet sniffing

### At Rest (Server Database)

Sensitive fields are encrypted using **Rails ActiveRecord Encryption** with AES-256-GCM:

**Encrypted fields:**
- Notes: `title`, `content`, `metadata`
- Messages: `content`, `metadata`
- Tasks: `title`, `description`
- Goals: Agent instructions, learnings
- User data: OAuth tokens, API keys

**Encryption keys:**
- Stored as environment variables in your `.env` file
- You control key rotation
- Previous keys retained for decryption during transition

**What this protects against:**
- ✅ Database breaches (data dumps are encrypted)
- ✅ Unauthorized database access
- ✅ Backup/snapshot leaks

**What this does NOT protect against:**
- ❌ Compromised server processes
- ❌ Attackers who gain access to your server (they can read `.env`)

### At Rest (iOS Local Cache)

All cached API responses are encrypted using **AES-256-GCM** before storage:

**Cached data:**
- Goals list
- Notes per goal
- Tasks per goal
- Chat message history

**Encryption implementation:**
- Algorithm: AES-256-GCM (authenticated encryption)
- Key generation: CryptoKit `SymmetricKey(size: .bits256)`
- Key storage: iOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`)
- Cache location: UserDefaults (encrypted values)
- Key lifecycle: Generated on first use, survives app reinstalls

**What this protects against:**
- ✅ Device theft (when unlocked)
- ✅ Malware reading UserDefaults
- ✅ Jailbreak attacks accessing app sandbox
- ✅ Unencrypted backup extraction

**What this does NOT protect against:**
- ❌ Malicious apps with root/jailbreak access
- ❌ Device unlocked with malware running
- ❌ Physical access to unlocked device

### At Rest (iOS Secure Storage)

Highly sensitive credentials are stored in **iOS Keychain**:

**Keychain-protected items:**
- User authentication tokens
- Device tokens
- Cache encryption keys

**Keychain properties:**
- Hardware-backed encryption (Secure Enclave on supported devices)
- Protected by device passcode/biometrics
- Isolated per-app (sandboxed)
- Survives app reinstalls
- Accessibility: `kSecAttrAccessibleAfterFirstUnlock` (accessible after first unlock, even when locked)

## Authentication & Authorization

### Token-Based Authentication

- **Device token**: Identifies the device, stored in Keychain
- **User token**: Identifies the user, stored in Keychain
- **Token format**: Signed JWT with expiration
- **Token transmission**: Authorization header (`Device <token>` or `User <token>`)
- **Token lifetime**: 90 days (automatic refresh on app launch)

### Authorization Model

- Device-scoped: Public data (no auth required)
- User-scoped: Private data (user token required)
- Goal-scoped: Per-goal data (user ownership validated server-side)

## What Houston Is NOT

### NOT End-to-End Encrypted

**Why?** Because Houston is an **AI agent system**, not a messaging app.

**What this means:**
- Your server can decrypt your data (you own it!)
- LLM providers (OpenAI, Anthropic) process your data when you make requests
- Since you self-host, only you have access to your server and data

**Why server-side processing?**
- AI agents need to read your data to help you
- LLM APIs run on external servers (OpenAI, Anthropic)
- Server-side features: search, task generation, proactive check-ins, SSE updates

**This is standard for AI-powered apps:**
- ChatGPT: Not E2E encrypted
- Notion AI: Not E2E encrypted
- GitHub Copilot: Not E2E encrypted

**Apps that ARE E2E encrypted (different use case):**
- Signal: Messaging
- 1Password: Password manager
- ProtonMail: Email

### NOT Zero-Knowledge

Houston processes your data server-side to provide AI features. Your self-hosted server stores:
- Your goals, notes, tasks
- Your chat message history
- Your agent activity

Houston does NOT store:
- Your device passcode
- Your biometric data
- Your OAuth passwords (only tokens from integrations like Plaid)

## Threat Model

### What We Protect Against ✅

| Threat | Protection | Effectiveness |
|--------|-----------|---------------|
| Network eavesdropping | TLS 1.3 | ✅ Strong |
| Database breach | Server-side encryption | ✅ Strong |
| Device theft (locked) | iOS device encryption | ✅ Strong |
| Device theft (unlocked) | iOS cache encryption | ✅ Strong |
| Malware reading cache | AES-256-GCM encryption | ✅ Strong |
| Backup extraction | Encrypted backups | ✅ Strong (if enabled) |
| Jailbreak/root access | Cache encryption + Keychain | ⚠️ Limited |

### What Houston Does NOT Protect Against ❌

| Threat | Why Not Protected |
|--------|-------------------|
| Server compromise | Attacker with server access can read `.env` and decrypt data |
| Compromised LLM providers | Data is sent to OpenAI/Anthropic for AI processing |
| Physical access to unlocked device | User is authenticated, app allows access |
| Advanced persistent threats | Beyond scope of consumer app security |

**Note for self-hosters:** You are responsible for securing your server. Use strong passwords, keep software updated, and consider a firewall.

## Data Retention & Deletion

### Active Data
- Stored as long as you use the service
- Encrypted at rest (server and iOS cache)
- Accessible to AI agents for processing

### Cache Expiry
- **iOS cache**: 24 hours
- **Server cache**: Varies by feature
- Auto-refresh on access if stale

### User Deletion
When you delete your account:
1. All user data deleted from database
2. iOS cache cleared immediately on logout
3. LLM provider logs retained per their policies (OpenAI/Anthropic) - you can request deletion from them directly

### Individual Item Deletion
- Notes, tasks, goals: Soft-deleted (recoverable for 30 days in the database)
- Chat messages: Hard-deleted immediately
- You control your own backup retention

## Compliance & Standards

### Frameworks
- OWASP Mobile Top 10
- iOS Security Guidelines (Apple)
- Rails Security Best Practices

### Practices
- ✅ Regular dependency updates
- ✅ Security-focused code reviews
- ✅ Encrypted data at rest and in transit
- ✅ Secure key management (environment variables + Keychain)
- ✅ Input validation and sanitization
- ✅ Rate limiting and abuse prevention

## Privacy & Data Access

### Who Can Access Your Data?

**You:**
- Full access to your data via iOS app
- Direct database access on your server
- You own all the data

**AI Providers (OpenAI, Anthropic, etc):**
- Process your data via API calls when you interact with Houston
- Subject to their privacy policies
- You can choose which providers to use via environment variables

### Self-Hosting Security Tips

1. **Secure your `.env` file**: Contains all encryption keys and API credentials
2. **Use HTTPS**: Set up TLS certificates for production deployments
3. **Keep Docker updated**: Regularly pull updated base images
4. **Limit network access**: Use a firewall to restrict access to your server
5. **Use strong passwords**: For any database or admin access
6. **Monitor logs**: Check for unusual activity in Rails and Docker logs
