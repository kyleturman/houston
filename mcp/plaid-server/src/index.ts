#!/usr/bin/env node

/**
 * Plaid MCP Server
 *
 * Provides financial data access through the Model Context Protocol (MCP)
 * Integrates with Plaid API for transactions, balances, and spending analysis
 *
 * Supports multiple connected institutions (banks/credit cards) simultaneously.
 * All tools automatically query all connected accounts unless filtered.
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ErrorCode,
  McpError
} from '@modelcontextprotocol/sdk/types.js';
import {
  Configuration,
  PlaidApi,
  PlaidEnvironments,
  Products,
  CountryCode,
  AccountsGetRequest,
  TransactionsGetRequest,
  TransactionsSyncRequest
} from 'plaid';
import { z } from 'zod';

// Environment variables
const PLAID_CLIENT_ID = process.env.PLAID_CLIENT_ID || '';
const PLAID_SECRET = process.env.PLAID_SECRET || '';
const PLAID_ENV = process.env.PLAID_ENV || 'sandbox';
const USER_ID = process.env.USER_ID || '';
const ACCESS_TOKEN = process.env.PLAID_ACCESS_TOKEN || '';

// Multi-connection support: PLAID_CONNECTIONS is a JSON array of connection objects
interface PlaidConnection {
  access_token: string;
  item_id: string;
  institution_name: string;
  institution_id: string;
  accounts: Array<{ id: string; name: string; mask: string; subtype: string }>;
}

function getConnections(): PlaidConnection[] {
  const connectionsJson = process.env.PLAID_CONNECTIONS;
  if (connectionsJson) {
    try {
      return JSON.parse(connectionsJson);
    } catch (e) {
      console.error('Failed to parse PLAID_CONNECTIONS:', e);
    }
  }
  // Fall back to single connection from ACCESS_TOKEN
  if (ACCESS_TOKEN) {
    return [{
      access_token: ACCESS_TOKEN,
      item_id: process.env.PLAID_ITEM_ID || '',
      institution_name: 'Unknown',
      institution_id: '',
      accounts: []
    }];
  }
  return [];
}

// Filter connections by institution name (case-insensitive partial match)
function filterConnectionsByInstitution(connections: PlaidConnection[], institutionName?: string): PlaidConnection[] {
  if (!institutionName) return connections;
  const searchTerm = institutionName.toLowerCase();
  return connections.filter(c => c.institution_name.toLowerCase().includes(searchTerm));
}

function ensureConnections(): PlaidConnection[] {
  const connections = getConnections();
  if (connections.length === 0) {
    throw new McpError(
      ErrorCode.InvalidRequest,
      'No Plaid connections available. Please connect a bank account first.'
    );
  }
  return connections;
}

// Initialize Plaid client
const configuration = new Configuration({
  basePath: PlaidEnvironments[PLAID_ENV as keyof typeof PlaidEnvironments],
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': PLAID_CLIENT_ID,
      'PLAID-SECRET': PLAID_SECRET,
    },
  },
});

const plaidClient = new PlaidApi(configuration);

// Create MCP server
const server = new Server(
  {
    name: 'plaid-financial-server',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Tool schemas using Zod - no accessToken needed, handled automatically
const GetAccountsSchema = z.object({
  institutionName: z.string().optional().describe('Filter by institution name (e.g., "Chase", "Ally")'),
});

const GetBalancesSchema = z.object({
  institutionName: z.string().optional().describe('Filter by institution name (e.g., "Chase", "Ally")'),
  accountIds: z.array(z.string()).optional().describe('Filter by specific account IDs'),
});

const GetTransactionsSchema = z.object({
  startDate: z.string().describe('Start date in YYYY-MM-DD format'),
  endDate: z.string().describe('End date in YYYY-MM-DD format'),
  institutionName: z.string().optional().describe('Filter by institution name (e.g., "Chase", "Ally")'),
  accountIds: z.array(z.string()).optional().describe('Filter by specific account IDs'),
  count: z.coerce.number().default(100).describe('Number of transactions to fetch per institution'),
});

const AnalyzeSpendingSchema = z.object({
  startDate: z.string().describe('Analysis start date in YYYY-MM-DD format'),
  endDate: z.string().describe('Analysis end date in YYYY-MM-DD format'),
  institutionName: z.string().optional().describe('Filter by institution name (e.g., "Chase", "Ally")'),
  accountIds: z.array(z.string()).optional().describe('Filter by specific account IDs'),
  categories: z.array(z.string()).optional().describe('Filter by specific Plaid categories'),
});

const GetRecurringTransactionsSchema = z.object({
  institutionName: z.string().optional().describe('Filter by institution name (e.g., "Chase", "Ally")'),
  accountIds: z.array(z.string()).optional().describe('Filter by specific account IDs'),
});

// Helper function to format currency
function formatCurrency(amount: number, currencyCode: string = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currencyCode,
  }).format(amount);
}

// Tool definitions
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'plaid_get_accounts',
        description: 'List all connected bank accounts and credit cards across all institutions. Returns account names, types (checking, savings, credit card, etc.), and institution info. Use this first to discover available accounts.',
        inputSchema: {
          type: 'object',
          properties: {
            institutionName: {
              type: 'string',
              description: 'Filter by institution name (e.g., "Chase", "Ally"). Partial match, case-insensitive.',
            },
          },
        },
      },
      {
        name: 'plaid_get_balances',
        description: 'Get current balances for all connected accounts. Shows current balance, available balance, and credit limits where applicable. Queries all connected institutions.',
        inputSchema: {
          type: 'object',
          properties: {
            institutionName: {
              type: 'string',
              description: 'Filter by institution name (e.g., "Chase", "Ally")',
            },
            accountIds: {
              type: 'array',
              items: { type: 'string' },
              description: 'Filter by specific account IDs (get IDs from plaid_get_accounts)',
            },
          },
        },
      },
      {
        name: 'plaid_get_transactions',
        description: 'Retrieve transactions within a date range from all connected accounts. Returns transaction details including merchant, amount, category, and date. Results are sorted by date (newest first). Example: plaid_get_transactions(startDate: "2025-12-06", endDate: "2025-12-07")',
        inputSchema: {
          type: 'object',
          properties: {
            startDate: {
              type: 'string',
              description: 'Start date in YYYY-MM-DD format (camelCase parameter)',
            },
            endDate: {
              type: 'string',
              description: 'End date in YYYY-MM-DD format (camelCase parameter)',
            },
            institutionName: {
              type: 'string',
              description: 'Filter by institution name (e.g., "Chase" for Chase credit card only)',
            },
            accountIds: {
              type: 'array',
              items: { type: 'string' },
              description: 'Filter by specific account IDs',
            },
            count: {
              type: 'number',
              description: 'Max transactions per institution (default: 100)',
              default: 100,
            },
          },
          required: ['startDate', 'endDate'],
        },
      },
      {
        name: 'plaid_analyze_spending',
        description: 'Analyze spending patterns across all connected accounts. Provides category breakdown, top merchants, unusual purchases detection, and daily spending averages. Can filter by institution or specific accounts. Example: plaid_analyze_spending(startDate: "2025-12-01", endDate: "2025-12-31")',
        inputSchema: {
          type: 'object',
          properties: {
            startDate: {
              type: 'string',
              description: 'Analysis start date in YYYY-MM-DD format (camelCase parameter)',
            },
            endDate: {
              type: 'string',
              description: 'Analysis end date in YYYY-MM-DD format (camelCase parameter)',
            },
            institutionName: {
              type: 'string',
              description: 'Filter by institution name (e.g., "Chase" to analyze only Chase spending)',
            },
            accountIds: {
              type: 'array',
              items: { type: 'string' },
              description: 'Filter by specific account IDs',
            },
            categories: {
              type: 'array',
              items: { type: 'string' },
              description: 'Filter by Plaid categories (e.g., ["Food and Drink", "Travel"])',
            },
          },
          required: ['startDate', 'endDate'],
        },
      },
      {
        name: 'plaid_get_recurring_transactions',
        description: 'Identify recurring transactions like subscriptions, bills, and regular income across all connected accounts.',
        inputSchema: {
          type: 'object',
          properties: {
            institutionName: {
              type: 'string',
              description: 'Filter by institution name',
            },
            accountIds: {
              type: 'array',
              items: { type: 'string' },
              description: 'Filter by specific account IDs',
            },
          },
        },
      },
    ],
  };
});

// Tool handler
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  try {
    const { name, arguments: args } = request.params;

    switch (name) {
      case 'plaid_get_accounts': {
        const params = GetAccountsSchema.parse(args);
        let connections = ensureConnections();
        connections = filterConnectionsByInstitution(connections, params.institutionName);

        if (connections.length === 0) {
          return {
            content: [{
              type: 'text',
              text: JSON.stringify({
                success: true,
                accounts: [],
                institutions: [],
                totalAccounts: 0,
                message: params.institutionName
                  ? `No accounts found for institution "${params.institutionName}"`
                  : 'No connected accounts found',
              }, null, 2),
            }],
          };
        }

        const allAccounts: any[] = [];
        const institutions: any[] = [];

        for (const conn of connections) {
          try {
            const response = await plaidClient.accountsGet({
              access_token: conn.access_token,
            });

            const accounts = response.data.accounts.map(account => ({
              accountId: account.account_id,
              name: account.name,
              officialName: account.official_name,
              type: account.type,
              subtype: account.subtype,
              mask: account.mask,
              institutionName: conn.institution_name,
              institutionId: conn.institution_id,
            }));

            allAccounts.push(...accounts);
            institutions.push({
              name: conn.institution_name,
              id: conn.institution_id,
              accountCount: accounts.length,
            });
          } catch (e: any) {
            console.error(`Error fetching accounts for ${conn.institution_name}:`, e.message);
          }
        }

        return {
          content: [{
            type: 'text',
            text: JSON.stringify({
              success: true,
              accounts: allAccounts,
              institutions,
              totalAccounts: allAccounts.length,
            }, null, 2),
          }],
        };
      }

      case 'plaid_get_balances': {
        const params = GetBalancesSchema.parse(args);
        let connections = ensureConnections();
        connections = filterConnectionsByInstitution(connections, params.institutionName);

        const allBalances: any[] = [];
        let totalBalance = 0;
        let totalDebt = 0;

        for (const conn of connections) {
          try {
            const request: AccountsGetRequest = {
              access_token: conn.access_token,
            };

            if (params.accountIds && params.accountIds.length > 0) {
              request.options = { account_ids: params.accountIds };
            }

            const response = await plaidClient.accountsGet(request);

            for (const account of response.data.accounts) {
              const isCredit = account.type === 'credit';
              const balance = {
                accountId: account.account_id,
                name: account.name,
                type: account.type,
                subtype: account.subtype,
                mask: account.mask,
                currentBalance: account.balances.current,
                availableBalance: account.balances.available,
                limit: account.balances.limit,
                formattedCurrent: formatCurrency(account.balances.current || 0, account.balances.iso_currency_code || 'USD'),
                formattedAvailable: formatCurrency(account.balances.available || 0, account.balances.iso_currency_code || 'USD'),
                formattedLimit: account.balances.limit ? formatCurrency(account.balances.limit, account.balances.iso_currency_code || 'USD') : null,
                institutionName: conn.institution_name,
              };

              allBalances.push(balance);

              if (isCredit) {
                totalDebt += account.balances.current || 0;
              } else {
                totalBalance += account.balances.current || 0;
              }
            }
          } catch (e: any) {
            console.error(`Error fetching balances for ${conn.institution_name}:`, e.message);
          }
        }

        return {
          content: [{
            type: 'text',
            text: JSON.stringify({
              success: true,
              balances: allBalances,
              summary: {
                totalAssets: formatCurrency(totalBalance),
                totalDebt: formatCurrency(totalDebt),
                netWorth: formatCurrency(totalBalance - totalDebt),
                accountCount: allBalances.length,
              },
            }, null, 2),
          }],
        };
      }

      case 'plaid_get_transactions': {
        const params = GetTransactionsSchema.parse(args);
        let connections = ensureConnections();
        connections = filterConnectionsByInstitution(connections, params.institutionName);

        const allTransactions: any[] = [];
        const accountsIncluded: any[] = [];
        let totalTransactions = 0;

        for (const conn of connections) {
          try {
            const request: TransactionsGetRequest = {
              access_token: conn.access_token,
              start_date: params.startDate,
              end_date: params.endDate,
              options: {
                count: params.count,
                offset: 0,
              },
            };

            if (params.accountIds && params.accountIds.length > 0) {
              request.options!.account_ids = params.accountIds;
            }

            const response = await plaidClient.transactionsGet(request);

            const transactions = response.data.transactions.map(txn => ({
              transactionId: txn.transaction_id,
              accountId: txn.account_id,
              amount: txn.amount,
              formattedAmount: formatCurrency(Math.abs(txn.amount), txn.iso_currency_code || 'USD'),
              isExpense: txn.amount > 0,
              date: txn.date,
              name: txn.name,
              merchantName: txn.merchant_name,
              category: txn.category,
              pending: txn.pending,
              institutionName: conn.institution_name,
            }));

            allTransactions.push(...transactions);
            totalTransactions += response.data.total_transactions;

            for (const acc of response.data.accounts) {
              accountsIncluded.push({
                id: acc.account_id,
                name: acc.name,
                type: acc.type,
                institutionName: conn.institution_name,
              });
            }
          } catch (e: any) {
            console.error(`Error fetching transactions for ${conn.institution_name}:`, e.message);
          }
        }

        // Sort by date descending
        allTransactions.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

        return {
          content: [{
            type: 'text',
            text: JSON.stringify({
              success: true,
              transactions: allTransactions,
              totalTransactions,
              accountsIncluded,
            }, null, 2),
          }],
        };
      }

      case 'plaid_analyze_spending': {
        const params = AnalyzeSpendingSchema.parse(args);
        let connections = ensureConnections();
        connections = filterConnectionsByInstitution(connections, params.institutionName);

        // Fetch transactions from all relevant connections
        const allTransactions: any[] = [];
        const institutionsSummary: any[] = [];

        for (const conn of connections) {
          try {
            const request: TransactionsGetRequest = {
              access_token: conn.access_token,
              start_date: params.startDate,
              end_date: params.endDate,
              options: { count: 500 },
            };

            if (params.accountIds && params.accountIds.length > 0) {
              request.options!.account_ids = params.accountIds;
            }

            const response = await plaidClient.transactionsGet(request);

            const txnsWithInstitution = response.data.transactions.map(txn => ({
              ...txn,
              institutionName: conn.institution_name,
            }));
            allTransactions.push(...txnsWithInstitution);
            institutionsSummary.push({
              name: conn.institution_name,
              transactionCount: response.data.transactions.length,
            });
          } catch (e: any) {
            console.error(`Error fetching transactions for ${conn.institution_name}:`, e.message);
          }
        }

        // Filter by categories if specified
        let filteredTransactions = allTransactions;
        if (params.categories && params.categories.length > 0) {
          filteredTransactions = allTransactions.filter(txn =>
            txn.category?.some((cat: string) => params.categories!.includes(cat))
          );
        }

        // Analyze spending
        const categorySpending = new Map<string, number>();
        const merchantSpending = new Map<string, number>();
        let totalSpending = 0;
        const expenses: any[] = [];

        filteredTransactions.forEach(txn => {
          // Positive amounts are expenses in Plaid
          if (txn.amount > 0) {
            totalSpending += txn.amount;
            expenses.push(txn);

            const category = txn.category?.[0] || 'Uncategorized';
            categorySpending.set(category, (categorySpending.get(category) || 0) + txn.amount);

            const merchant = txn.merchant_name || txn.name;
            merchantSpending.set(merchant, (merchantSpending.get(merchant) || 0) + txn.amount);
          }
        });

        // Find unusual purchases (>2 std dev from mean)
        const amounts = expenses.map(txn => txn.amount);
        const mean = amounts.length > 0 ? amounts.reduce((sum, val) => sum + val, 0) / amounts.length : 0;
        const variance = amounts.length > 0 ? amounts.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / amounts.length : 0;
        const stdDev = Math.sqrt(variance);
        const threshold = mean + (2 * stdDev);

        const unusualPurchases = expenses
          .filter(txn => txn.amount > threshold && threshold > 0)
          .map(txn => ({
            date: txn.date,
            name: txn.name,
            merchantName: txn.merchant_name,
            amount: formatCurrency(txn.amount, txn.iso_currency_code || 'USD'),
            category: txn.category,
            institutionName: txn.institutionName,
          }));

        const topCategories = Array.from(categorySpending.entries())
          .sort((a, b) => b[1] - a[1])
          .slice(0, 10)
          .map(([category, amount]) => ({
            category,
            amount: formatCurrency(amount),
            percentage: totalSpending > 0 ? ((amount / totalSpending) * 100).toFixed(1) + '%' : '0%',
          }));

        const topMerchants = Array.from(merchantSpending.entries())
          .sort((a, b) => b[1] - a[1])
          .slice(0, 10)
          .map(([merchant, amount]) => ({
            merchant,
            amount: formatCurrency(amount),
            percentage: totalSpending > 0 ? ((amount / totalSpending) * 100).toFixed(1) + '%' : '0%',
          }));

        const dayCount = Math.max(1, Math.ceil(
          (new Date(params.endDate).getTime() - new Date(params.startDate).getTime()) / (1000 * 60 * 60 * 24)
        ));

        return {
          content: [{
            type: 'text',
            text: JSON.stringify({
              success: true,
              summary: {
                totalSpending: formatCurrency(totalSpending),
                transactionCount: expenses.length,
                averageTransaction: formatCurrency(mean),
                averageDailySpending: formatCurrency(totalSpending / dayCount),
                dateRange: { start: params.startDate, end: params.endDate },
              },
              topCategories,
              topMerchants,
              unusualPurchases,
              institutionsSummary,
            }, null, 2),
          }],
        };
      }

      case 'plaid_get_recurring_transactions': {
        const params = GetRecurringTransactionsSchema.parse(args);
        let connections = ensureConnections();
        connections = filterConnectionsByInstitution(connections, params.institutionName);

        const allInflowStreams: any[] = [];
        const allOutflowStreams: any[] = [];

        for (const conn of connections) {
          try {
            const request: any = {
              access_token: conn.access_token,
            };

            if (params.accountIds && params.accountIds.length > 0) {
              request.account_ids = params.accountIds;
            }

            const response = await plaidClient.transactionsRecurringGet(request);

            const inflowStreams = response.data.inflow_streams.map(stream => ({
              streamId: stream.stream_id,
              description: stream.description,
              merchantName: stream.merchant_name,
              category: stream.category,
              frequency: stream.frequency,
              averageAmount: formatCurrency(stream.average_amount.amount || 0, stream.average_amount.iso_currency_code || 'USD'),
              lastAmount: formatCurrency(stream.last_amount.amount || 0, stream.last_amount.iso_currency_code || 'USD'),
              isActive: stream.is_active,
              lastDate: stream.last_date,
              institutionName: conn.institution_name,
            }));

            const outflowStreams = response.data.outflow_streams.map(stream => ({
              streamId: stream.stream_id,
              description: stream.description,
              merchantName: stream.merchant_name,
              category: stream.category,
              frequency: stream.frequency,
              averageAmount: formatCurrency(stream.average_amount.amount || 0, stream.average_amount.iso_currency_code || 'USD'),
              lastAmount: formatCurrency(stream.last_amount.amount || 0, stream.last_amount.iso_currency_code || 'USD'),
              isActive: stream.is_active,
              lastDate: stream.last_date,
              institutionName: conn.institution_name,
            }));

            allInflowStreams.push(...inflowStreams);
            allOutflowStreams.push(...outflowStreams);
          } catch (e: any) {
            console.error(`Error fetching recurring for ${conn.institution_name}:`, e.message);
          }
        }

        return {
          content: [{
            type: 'text',
            text: JSON.stringify({
              success: true,
              recurringIncome: {
                count: allInflowStreams.length,
                streams: allInflowStreams,
              },
              recurringExpenses: {
                count: allOutflowStreams.length,
                streams: allOutflowStreams,
              },
            }, null, 2),
          }],
        };
      }

      default:
        throw new McpError(
          ErrorCode.MethodNotFound,
          `Unknown tool: ${name}`
        );
    }
  } catch (error) {
    if (error instanceof McpError) {
      throw error;
    }

    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new McpError(
      ErrorCode.InternalError,
      `Tool execution failed: ${errorMessage}`
    );
  }
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Plaid MCP server running on stdio');
}

main().catch((error) => {
  console.error('Server error:', error);
  process.exit(1);
});
