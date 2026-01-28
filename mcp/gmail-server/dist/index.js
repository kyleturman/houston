#!/usr/bin/env node
/**
 * Gmail MCP Server
 *
 * Provides Gmail access through the Model Context Protocol (MCP).
 * Supports multiple connected Google accounts simultaneously.
 * All tools automatically query all connected accounts unless filtered.
 */
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema, ErrorCode, McpError } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { GmailClient } from './gmail-client.js';
// Multi-connection support: GOOGLE_CONNECTIONS is a JSON array of connection objects
function getConnections() {
    const connectionsJson = process.env.GOOGLE_CONNECTIONS;
    if (connectionsJson) {
        try {
            return JSON.parse(connectionsJson);
        }
        catch (e) {
            console.error('Failed to parse GOOGLE_CONNECTIONS:', e);
        }
    }
    // Fall back to single connection from legacy env vars
    if (process.env.GOOGLE_API_ACCESS_TOKEN) {
        return [{
                email: process.env.GOOGLE_USER_EMAIL || 'unknown',
                access_token: process.env.GOOGLE_API_ACCESS_TOKEN,
                refresh_token: process.env.GOOGLE_REFRESH_TOKEN || '',
                expires_at: '',
            }];
    }
    return [];
}
// Filter connections by email (case-insensitive partial match)
function filterConnectionsByEmail(connections, email) {
    if (!email)
        return connections;
    const searchTerm = email.toLowerCase();
    return connections.filter(c => c.email.toLowerCase().includes(searchTerm));
}
function ensureConnections() {
    const connections = getConnections();
    if (connections.length === 0) {
        throw new McpError(ErrorCode.InvalidRequest, 'No Google accounts connected. Please connect a Google account first.');
    }
    return connections;
}
// Create MCP server
const server = new Server({
    name: 'gmail-mcp-server',
    version: '1.0.0',
}, {
    capabilities: {
        tools: {},
    },
});
// Tool schemas using Zod
const SearchSchema = z.object({
    query: z.string().describe('Gmail search query (same syntax as Gmail search box). Examples: "from:user@example.com", "is:unread", "subject:invoice", "after:2025/01/01"'),
    accountEmail: z.string().optional().describe('Filter by account email (partial match, case-insensitive)'),
    maxResults: z.coerce.number().default(20).describe('Maximum number of results (default: 20)'),
    includeSpamTrash: z.boolean().default(false).describe('Include spam and trash folders'),
});
const ReadEmailSchema = z.object({
    messageId: z.string().describe('Gmail message ID'),
    accountEmail: z.string().optional().describe('Filter by account email to find the message'),
    format: z.enum(['full', 'metadata', 'minimal']).default('full').describe('Amount of detail to return'),
});
const GetThreadSchema = z.object({
    threadId: z.string().describe('Gmail thread ID'),
    accountEmail: z.string().optional().describe('Filter by account email to find the thread'),
    format: z.enum(['full', 'metadata', 'minimal']).default('full').describe('Amount of detail to return'),
});
const SendEmailSchema = z.object({
    to: z.array(z.string()).describe('Recipient email addresses'),
    subject: z.string().describe('Email subject'),
    body: z.string().describe('Email body content'),
    accountEmail: z.string().optional().describe('Account to send from (uses first account if not specified)'),
    cc: z.array(z.string()).optional().describe('CC recipients'),
    bcc: z.array(z.string()).optional().describe('BCC recipients'),
    isHtml: z.boolean().default(false).describe('Whether body is HTML (default: plain text)'),
    replyToMessageId: z.string().optional().describe('Message ID to reply to'),
    threadId: z.string().optional().describe('Thread ID to add this message to'),
});
const CreateDraftSchema = z.object({
    to: z.array(z.string()).describe('Recipient email addresses'),
    subject: z.string().describe('Email subject'),
    body: z.string().describe('Email body content'),
    accountEmail: z.string().optional().describe('Account to create draft in (uses first account if not specified)'),
    cc: z.array(z.string()).optional().describe('CC recipients'),
    bcc: z.array(z.string()).optional().describe('BCC recipients'),
    isHtml: z.boolean().default(false).describe('Whether body is HTML (default: plain text)'),
});
const ListLabelsSchema = z.object({
    accountEmail: z.string().optional().describe('Filter by account email'),
});
// Tool definitions
server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
        tools: [
            {
                name: 'gmail_search',
                description: 'Search for emails across all connected Google accounts using Gmail query syntax. Returns email metadata including subject, from, date, and snippet. Results are merged from all accounts unless filtered. Examples: "from:boss@company.com", "is:unread subject:urgent", "after:2025/01/01 has:attachment"',
                inputSchema: {
                    type: 'object',
                    properties: {
                        query: {
                            type: 'string',
                            description: 'Gmail search query (same syntax as Gmail search box)',
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Filter to specific account (partial match, case-insensitive)',
                        },
                        maxResults: {
                            type: 'number',
                            description: 'Maximum results to return (default: 20)',
                            default: 20,
                        },
                        includeSpamTrash: {
                            type: 'boolean',
                            description: 'Include spam and trash folders',
                            default: false,
                        },
                    },
                    required: ['query'],
                },
            },
            {
                name: 'gmail_read_email',
                description: 'Get the full content of a specific email by its message ID. Returns subject, from, to, body, attachments info, and labels.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        messageId: {
                            type: 'string',
                            description: 'Gmail message ID (from search results)',
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Account email to search in (tries all if not specified)',
                        },
                        format: {
                            type: 'string',
                            enum: ['full', 'metadata', 'minimal'],
                            description: 'Amount of detail (default: full)',
                            default: 'full',
                        },
                    },
                    required: ['messageId'],
                },
            },
            {
                name: 'gmail_get_thread',
                description: 'Get all messages in an email thread/conversation. Returns the complete conversation with all replies.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        threadId: {
                            type: 'string',
                            description: 'Gmail thread ID',
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Account email to search in (tries all if not specified)',
                        },
                        format: {
                            type: 'string',
                            enum: ['full', 'metadata', 'minimal'],
                            description: 'Amount of detail (default: full)',
                            default: 'full',
                        },
                    },
                    required: ['threadId'],
                },
            },
            {
                name: 'gmail_send',
                description: 'Send an email from a connected Google account. Can send new emails or replies to existing threads.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        to: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'Recipient email addresses',
                        },
                        subject: {
                            type: 'string',
                            description: 'Email subject',
                        },
                        body: {
                            type: 'string',
                            description: 'Email body content',
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Account to send from (uses first account if not specified)',
                        },
                        cc: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'CC recipients',
                        },
                        bcc: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'BCC recipients',
                        },
                        isHtml: {
                            type: 'boolean',
                            description: 'Whether body is HTML (default: plain text)',
                            default: false,
                        },
                        replyToMessageId: {
                            type: 'string',
                            description: 'Message ID to reply to',
                        },
                        threadId: {
                            type: 'string',
                            description: 'Thread ID to add this message to',
                        },
                    },
                    required: ['to', 'subject', 'body'],
                },
            },
            {
                name: 'gmail_create_draft',
                description: 'Create a draft email without sending it. The draft will be saved to the Drafts folder.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        to: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'Recipient email addresses',
                        },
                        subject: {
                            type: 'string',
                            description: 'Email subject',
                        },
                        body: {
                            type: 'string',
                            description: 'Email body content',
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Account to create draft in (uses first account if not specified)',
                        },
                        cc: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'CC recipients',
                        },
                        bcc: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'BCC recipients',
                        },
                        isHtml: {
                            type: 'boolean',
                            description: 'Whether body is HTML (default: plain text)',
                            default: false,
                        },
                    },
                    required: ['to', 'subject', 'body'],
                },
            },
            {
                name: 'gmail_list_labels',
                description: 'List all labels/folders in Gmail accounts. Returns both system labels (INBOX, SENT, etc.) and user-created labels.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        accountEmail: {
                            type: 'string',
                            description: 'Filter to specific account (partial match)',
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
            case 'gmail_search': {
                const params = SearchSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                if (connections.length === 0) {
                    return {
                        content: [{
                                type: 'text',
                                text: JSON.stringify({
                                    success: true,
                                    messages: [],
                                    totalResults: 0,
                                    message: params.accountEmail
                                        ? `No accounts match "${params.accountEmail}"`
                                        : 'No connected accounts found',
                                }, null, 2),
                            }],
                    };
                }
                const allMessages = [];
                for (const conn of connections) {
                    try {
                        const client = new GmailClient(conn);
                        const messages = await client.search(params.query, params.maxResults, params.includeSpamTrash);
                        allMessages.push(...messages);
                    }
                    catch (e) {
                        console.error(`Error searching ${conn.email}:`, e.message);
                    }
                }
                // Sort by date descending (newest first)
                allMessages.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
                // Limit total results
                const limitedMessages = allMessages.slice(0, params.maxResults);
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                messages: limitedMessages.map(m => ({
                                    id: m.id,
                                    threadId: m.threadId,
                                    subject: m.subject,
                                    from: m.from,
                                    to: m.to,
                                    date: m.date,
                                    snippet: m.snippet,
                                    isUnread: m.isUnread,
                                    hasAttachments: m.hasAttachments,
                                    labels: m.labels,
                                    accountEmail: m.accountEmail,
                                })),
                                totalResults: limitedMessages.length,
                                accountsSearched: connections.map(c => c.email),
                            }, null, 2),
                        }],
                };
            }
            case 'gmail_read_email': {
                const params = ReadEmailSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                let message = null;
                let foundInAccount = null;
                // Try each connection until we find the message
                for (const conn of connections) {
                    try {
                        const client = new GmailClient(conn);
                        message = await client.getMessage(params.messageId, params.format);
                        if (message) {
                            foundInAccount = conn.email;
                            break;
                        }
                    }
                    catch (e) {
                        // Continue to next account
                    }
                }
                if (!message) {
                    return {
                        content: [{
                                type: 'text',
                                text: JSON.stringify({
                                    success: false,
                                    error: `Message ${params.messageId} not found in any connected account`,
                                }, null, 2),
                            }],
                    };
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                message: {
                                    id: message.id,
                                    threadId: message.threadId,
                                    subject: message.subject,
                                    from: message.from,
                                    to: message.to,
                                    cc: message.cc,
                                    bcc: message.bcc,
                                    date: message.date,
                                    body: message.body,
                                    bodyHtml: message.bodyHtml ? '[HTML content available]' : undefined,
                                    isUnread: message.isUnread,
                                    hasAttachments: message.hasAttachments,
                                    labels: message.labels,
                                    accountEmail: message.accountEmail,
                                },
                            }, null, 2),
                        }],
                };
            }
            case 'gmail_get_thread': {
                const params = GetThreadSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                let thread = null;
                // Try each connection until we find the thread
                for (const conn of connections) {
                    try {
                        const client = new GmailClient(conn);
                        thread = await client.getThread(params.threadId, params.format);
                        if (thread) {
                            break;
                        }
                    }
                    catch (e) {
                        // Continue to next account
                    }
                }
                if (!thread) {
                    return {
                        content: [{
                                type: 'text',
                                text: JSON.stringify({
                                    success: false,
                                    error: `Thread ${params.threadId} not found in any connected account`,
                                }, null, 2),
                            }],
                    };
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                thread: {
                                    id: thread.id,
                                    subject: thread.subject,
                                    snippet: thread.snippet,
                                    messageCount: thread.messageCount,
                                    accountEmail: thread.accountEmail,
                                    messages: thread.messages.map(m => ({
                                        id: m.id,
                                        from: m.from,
                                        to: m.to,
                                        date: m.date,
                                        body: m.body,
                                        isUnread: m.isUnread,
                                    })),
                                },
                            }, null, 2),
                        }],
                };
            }
            case 'gmail_send': {
                const params = SendEmailSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                if (connections.length === 0) {
                    throw new McpError(ErrorCode.InvalidRequest, params.accountEmail
                        ? `No account matches "${params.accountEmail}"`
                        : 'No connected accounts available');
                }
                // Use the first matching account
                const conn = connections[0];
                const client = new GmailClient(conn);
                const sentMessage = await client.sendEmail({
                    to: params.to,
                    subject: params.subject,
                    body: params.body,
                    cc: params.cc,
                    bcc: params.bcc,
                    isHtml: params.isHtml,
                    replyToMessageId: params.replyToMessageId,
                    threadId: params.threadId,
                });
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                message: 'Email sent successfully',
                                sentFrom: conn.email,
                                messageId: sentMessage.id,
                                threadId: sentMessage.threadId,
                                to: params.to,
                                subject: params.subject,
                            }, null, 2),
                        }],
                };
            }
            case 'gmail_create_draft': {
                const params = CreateDraftSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                if (connections.length === 0) {
                    throw new McpError(ErrorCode.InvalidRequest, params.accountEmail
                        ? `No account matches "${params.accountEmail}"`
                        : 'No connected accounts available');
                }
                const conn = connections[0];
                const client = new GmailClient(conn);
                const draft = await client.createDraft({
                    to: params.to,
                    subject: params.subject,
                    body: params.body,
                    cc: params.cc,
                    bcc: params.bcc,
                    isHtml: params.isHtml,
                });
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                message: 'Draft created successfully',
                                accountEmail: conn.email,
                                draftId: draft.draftId,
                                messageId: draft.message.id,
                                to: params.to,
                                subject: params.subject,
                            }, null, 2),
                        }],
                };
            }
            case 'gmail_list_labels': {
                const params = ListLabelsSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                const allLabels = [];
                for (const conn of connections) {
                    try {
                        const client = new GmailClient(conn);
                        const labels = await client.listLabels();
                        allLabels.push(...labels);
                    }
                    catch (e) {
                        console.error(`Error listing labels for ${conn.email}:`, e.message);
                    }
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                labels: allLabels,
                                totalLabels: allLabels.length,
                                accountsQueried: connections.map(c => c.email),
                            }, null, 2),
                        }],
                };
            }
            default:
                throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
        }
    }
    catch (error) {
        if (error instanceof McpError) {
            throw error;
        }
        const errorMessage = error instanceof Error ? error.message : String(error);
        // Check for common Google API errors
        if (errorMessage.includes('invalid_grant') || errorMessage.includes('Token has been expired')) {
            throw new McpError(ErrorCode.InvalidRequest, 'Google access token has expired. Please reconnect the account.');
        }
        if (errorMessage.includes('insufficient permission') || errorMessage.includes('403')) {
            throw new McpError(ErrorCode.InvalidRequest, 'Insufficient Gmail permissions. Please reconnect with the required scopes.');
        }
        throw new McpError(ErrorCode.InternalError, `Gmail operation failed: ${errorMessage}`);
    }
});
// Start server
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error('Gmail MCP server running on stdio');
}
main().catch((error) => {
    console.error('Server error:', error);
    process.exit(1);
});
//# sourceMappingURL=index.js.map