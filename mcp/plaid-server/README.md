# Plaid MCP Server

Model Context Protocol server for Plaid financial data integration with Houston.

## Features

- **Account Management**: List all connected bank accounts
- **Balance Tracking**: Get current and available balances
- **Transaction Fetching**: Retrieve transactions by date range
- **Transaction Sync**: Incremental sync using cursors
- **Spending Analysis**: Categorize expenses, find unusual purchases, budget insights
- **Recurring Detection**: Identify subscriptions and recurring bills
- **Link Token Creation**: Initialize Plaid Link for new connections

## Tools

### `plaid_create_link_token`
Create a Link token to initialize Plaid Link for bank account connection.

**Parameters:**
- `userId` (required): Unique user identifier
- `redirectUri` (optional): OAuth redirect URI
- `products` (optional): Array of Plaid products (default: ['transactions', 'auth'])

### `plaid_exchange_public_token`
Exchange public token from Plaid Link for an access token.

**Parameters:**
- `publicToken` (required): Public token from Plaid Link
- `userId` (required): User identifier

### `plaid_get_accounts`
Fetch all connected bank accounts.

**Parameters:**
- `accessToken` (optional): Uses env var if not provided

### `plaid_get_balances`
Get current balances for accounts.

**Parameters:**
- `accessToken` (optional): Uses env var if not provided
- `accountIds` (optional): Filter by specific accounts

### `plaid_get_transactions`
Retrieve transactions within a date range.

**Parameters:**
- `startDate` (required): YYYY-MM-DD format
- `endDate` (required): YYYY-MM-DD format
- `accessToken` (optional): Uses env var if not provided
- `accountIds` (optional): Filter by specific accounts
- `count` (optional): Number of transactions (default: 100)
- `offset` (optional): Pagination offset (default: 0)

### `plaid_sync_transactions`
Perform incremental transaction sync.

**Parameters:**
- `accessToken` (optional): Uses env var if not provided
- `cursor` (optional): Cursor for incremental sync

### `plaid_analyze_spending`
Analyze spending patterns and identify unusual purchases.

**Parameters:**
- `startDate` (required): YYYY-MM-DD format
- `endDate` (required): YYYY-MM-DD format
- `accessToken` (optional): Uses env var if not provided
- `categories` (optional): Filter by categories

**Returns:**
- Total spending summary
- Top categories by spending
- Top merchants
- Unusual purchases (>2σ from mean)
- Daily spending insights

### `plaid_get_recurring_transactions`
Identify recurring transactions (subscriptions, bills).

**Parameters:**
- `accessToken` (optional): Uses env var if not provided
- `accountIds` (optional): Filter by specific accounts

## Environment Variables

Required:
- `PLAID_CLIENT_ID`: Plaid client ID from dashboard
- `PLAID_SECRET`: Plaid secret from dashboard

Optional:
- `PLAID_ENV`: Environment (sandbox, development, production) - default: sandbox
- `PLAID_ACCESS_TOKEN`: Default access token for user
- `USER_ID`: Default user ID

## Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Build
npm run build

# Run production
npm start
```

## Docker

```bash
# Build image
docker build -t mcp/plaid .

# Run
docker run -i --rm \
  -e PLAID_CLIENT_ID=your_client_id \
  -e PLAID_SECRET=your_secret \
  -e PLAID_ENV=sandbox \
  mcp/plaid
```

## Integration with Houston

The server is configured in `/mcp/local_servers.json` and runs as a Docker container.
User access tokens are stored in the `plaid_connections` table and passed via environment variables.

## Testing

Use Plaid's sandbox environment for testing:
- No real bank credentials needed
- Test data available
- Free to use
- Get credentials at https://dashboard.plaid.com/
