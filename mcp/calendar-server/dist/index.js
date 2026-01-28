#!/usr/bin/env node
/**
 * Google Calendar MCP Server
 *
 * Provides calendar management through the Model Context Protocol (MCP).
 * Supports multiple connected Google accounts simultaneously.
 * All tools automatically query all connected accounts unless filtered.
 */
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema, ErrorCode, McpError } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { CalendarClient } from './calendar-client.js';
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
    name: 'calendar-mcp-server',
    version: '1.0.0',
}, {
    capabilities: {
        tools: {},
    },
});
// Event date/time schema
const EventDateTimeSchema = z.object({
    dateTime: z.string().optional().describe('ISO8601 date-time for timed events (e.g., "2025-01-10T10:00:00-05:00")'),
    date: z.string().optional().describe('YYYY-MM-DD for all-day events'),
    timeZone: z.string().optional().describe('Timezone (e.g., "America/New_York")'),
}).refine(data => data.dateTime || data.date, {
    message: 'Either dateTime or date must be provided',
});
// Tool schemas using Zod
const ListCalendarsSchema = z.object({
    accountEmail: z.string().optional().describe('Filter by account email (partial match, case-insensitive)'),
});
const ListEventsSchema = z.object({
    accountEmail: z.string().optional().describe('Filter by account email'),
    calendarId: z.string().optional().describe('Calendar ID (default: "primary")'),
    timeMin: z.string().optional().describe('Start of time range (ISO8601). Default: now'),
    timeMax: z.string().optional().describe('End of time range (ISO8601). Default: 7 days from now'),
    maxResults: z.coerce.number().optional().describe('Maximum events to return (default: 50)'),
    singleEvents: z.boolean().optional().describe('Expand recurring events (default: true)'),
    orderBy: z.enum(['startTime', 'updated']).optional().describe('Sort order (default: startTime)'),
    q: z.string().optional().describe('Search query to filter events'),
});
const GetEventSchema = z.object({
    eventId: z.string().describe('Event ID'),
    accountEmail: z.string().optional().describe('Filter by account email'),
    calendarId: z.string().optional().describe('Calendar ID (default: "primary")'),
});
const CreateEventSchema = z.object({
    summary: z.string().describe('Event title'),
    start: EventDateTimeSchema.describe('Event start time'),
    end: EventDateTimeSchema.describe('Event end time'),
    accountEmail: z.string().optional().describe('Account to create event in (uses first if not specified)'),
    calendarId: z.string().optional().describe('Calendar ID (default: "primary")'),
    description: z.string().optional().describe('Event description'),
    location: z.string().optional().describe('Event location'),
    attendees: z.array(z.string()).optional().describe('Attendee email addresses'),
    sendUpdates: z.enum(['all', 'externalOnly', 'none']).optional().describe('Send notifications (default: all)'),
    timeZone: z.string().optional().describe('Timezone for the event'),
    colorId: z.string().optional().describe('Color ID (1-11)'),
});
const UpdateEventSchema = z.object({
    eventId: z.string().describe('Event ID to update'),
    accountEmail: z.string().optional().describe('Filter by account email'),
    calendarId: z.string().optional().describe('Calendar ID (default: "primary")'),
    summary: z.string().optional().describe('New event title'),
    description: z.string().optional().describe('New event description'),
    location: z.string().optional().describe('New event location'),
    start: EventDateTimeSchema.optional().describe('New start time'),
    end: EventDateTimeSchema.optional().describe('New end time'),
    attendees: z.array(z.string()).optional().describe('New attendee list (replaces existing)'),
    sendUpdates: z.enum(['all', 'externalOnly', 'none']).optional().describe('Send notifications'),
    colorId: z.string().optional().describe('Color ID (1-11)'),
});
const DeleteEventSchema = z.object({
    eventId: z.string().describe('Event ID to delete'),
    accountEmail: z.string().optional().describe('Filter by account email'),
    calendarId: z.string().optional().describe('Calendar ID (default: "primary")'),
    sendUpdates: z.enum(['all', 'externalOnly', 'none']).optional().describe('Send notifications'),
});
const FreeBusySchema = z.object({
    timeMin: z.string().describe('Start of time range (ISO8601)'),
    timeMax: z.string().describe('End of time range (ISO8601)'),
    accountEmail: z.string().optional().describe('Filter by account email'),
    calendarIds: z.array(z.string()).optional().describe('Calendar IDs to check (default: ["primary"])'),
});
// Tool definitions
server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
        tools: [
            {
                name: 'calendar_list_calendars',
                description: 'List all calendars across connected Google accounts. Returns calendar names, IDs, colors, and access levels.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        accountEmail: {
                            type: 'string',
                            description: 'Filter to specific account (partial match, case-insensitive)',
                        },
                    },
                },
            },
            {
                name: 'calendar_list_events',
                description: 'Get calendar events within a time range. By default returns events for the next 7 days. Results are merged from all accounts unless filtered.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        accountEmail: {
                            type: 'string',
                            description: 'Filter to specific account',
                        },
                        calendarId: {
                            type: 'string',
                            description: 'Calendar ID (default: "primary")',
                        },
                        timeMin: {
                            type: 'string',
                            description: 'Start of time range (ISO8601). Default: now',
                        },
                        timeMax: {
                            type: 'string',
                            description: 'End of time range (ISO8601). Default: 7 days from now',
                        },
                        maxResults: {
                            type: 'number',
                            description: 'Maximum events per account (default: 50)',
                        },
                        singleEvents: {
                            type: 'boolean',
                            description: 'Expand recurring events (default: true)',
                        },
                        orderBy: {
                            type: 'string',
                            enum: ['startTime', 'updated'],
                            description: 'Sort order (default: startTime)',
                        },
                        q: {
                            type: 'string',
                            description: 'Search query to filter events',
                        },
                    },
                },
            },
            {
                name: 'calendar_get_event',
                description: 'Get details of a specific calendar event by ID.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        eventId: {
                            type: 'string',
                            description: 'Event ID',
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Account to search in (tries all if not specified)',
                        },
                        calendarId: {
                            type: 'string',
                            description: 'Calendar ID (default: "primary")',
                        },
                    },
                    required: ['eventId'],
                },
            },
            {
                name: 'calendar_create_event',
                description: 'Create a new calendar event. For all-day events, use date format "YYYY-MM-DD". For timed events, use ISO8601 dateTime format.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        summary: {
                            type: 'string',
                            description: 'Event title',
                        },
                        start: {
                            type: 'object',
                            description: 'Event start time',
                            properties: {
                                dateTime: { type: 'string', description: 'ISO8601 for timed events' },
                                date: { type: 'string', description: 'YYYY-MM-DD for all-day events' },
                                timeZone: { type: 'string', description: 'Timezone (e.g., "America/New_York")' },
                            },
                        },
                        end: {
                            type: 'object',
                            description: 'Event end time',
                            properties: {
                                dateTime: { type: 'string', description: 'ISO8601 for timed events' },
                                date: { type: 'string', description: 'YYYY-MM-DD for all-day events' },
                                timeZone: { type: 'string', description: 'Timezone' },
                            },
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Account to create event in (uses first if not specified)',
                        },
                        calendarId: {
                            type: 'string',
                            description: 'Calendar ID (default: "primary")',
                        },
                        description: { type: 'string', description: 'Event description' },
                        location: { type: 'string', description: 'Event location' },
                        attendees: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'Attendee email addresses',
                        },
                        sendUpdates: {
                            type: 'string',
                            enum: ['all', 'externalOnly', 'none'],
                            description: 'Send notifications (default: all)',
                        },
                        timeZone: { type: 'string', description: 'Timezone for the event' },
                    },
                    required: ['summary', 'start', 'end'],
                },
            },
            {
                name: 'calendar_update_event',
                description: 'Update an existing calendar event. Only specified fields will be modified.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        eventId: { type: 'string', description: 'Event ID to update' },
                        accountEmail: { type: 'string', description: 'Account containing the event' },
                        calendarId: { type: 'string', description: 'Calendar ID (default: "primary")' },
                        summary: { type: 'string', description: 'New event title' },
                        description: { type: 'string', description: 'New description' },
                        location: { type: 'string', description: 'New location' },
                        start: {
                            type: 'object',
                            description: 'New start time',
                            properties: {
                                dateTime: { type: 'string' },
                                date: { type: 'string' },
                                timeZone: { type: 'string' },
                            },
                        },
                        end: {
                            type: 'object',
                            description: 'New end time',
                            properties: {
                                dateTime: { type: 'string' },
                                date: { type: 'string' },
                                timeZone: { type: 'string' },
                            },
                        },
                        attendees: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'New attendee list (replaces existing)',
                        },
                        sendUpdates: {
                            type: 'string',
                            enum: ['all', 'externalOnly', 'none'],
                        },
                    },
                    required: ['eventId'],
                },
            },
            {
                name: 'calendar_delete_event',
                description: 'Delete a calendar event.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        eventId: { type: 'string', description: 'Event ID to delete' },
                        accountEmail: { type: 'string', description: 'Account containing the event' },
                        calendarId: { type: 'string', description: 'Calendar ID (default: "primary")' },
                        sendUpdates: {
                            type: 'string',
                            enum: ['all', 'externalOnly', 'none'],
                            description: 'Send cancellation notifications',
                        },
                    },
                    required: ['eventId'],
                },
            },
            {
                name: 'calendar_free_busy',
                description: 'Check availability / find free time slots across calendars. Returns busy time periods.',
                inputSchema: {
                    type: 'object',
                    properties: {
                        timeMin: {
                            type: 'string',
                            description: 'Start of time range (ISO8601)',
                        },
                        timeMax: {
                            type: 'string',
                            description: 'End of time range (ISO8601)',
                        },
                        accountEmail: {
                            type: 'string',
                            description: 'Filter to specific account',
                        },
                        calendarIds: {
                            type: 'array',
                            items: { type: 'string' },
                            description: 'Calendar IDs to check (default: ["primary"])',
                        },
                    },
                    required: ['timeMin', 'timeMax'],
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
            case 'calendar_list_calendars': {
                const params = ListCalendarsSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                const allCalendars = [];
                for (const conn of connections) {
                    try {
                        const client = new CalendarClient(conn);
                        const calendars = await client.listCalendars();
                        allCalendars.push(...calendars);
                    }
                    catch (e) {
                        console.error(`Error listing calendars for ${conn.email}:`, e.message);
                    }
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                calendars: allCalendars,
                                totalCalendars: allCalendars.length,
                                accountsQueried: connections.map(c => c.email),
                            }, null, 2),
                        }],
                };
            }
            case 'calendar_list_events': {
                const params = ListEventsSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                const allEvents = [];
                for (const conn of connections) {
                    try {
                        const client = new CalendarClient(conn);
                        const events = await client.listEvents({
                            calendarId: params.calendarId,
                            timeMin: params.timeMin,
                            timeMax: params.timeMax,
                            maxResults: params.maxResults,
                            singleEvents: params.singleEvents,
                            orderBy: params.orderBy,
                            q: params.q,
                        });
                        allEvents.push(...events);
                    }
                    catch (e) {
                        console.error(`Error listing events for ${conn.email}:`, e.message);
                    }
                }
                // Sort by start time
                allEvents.sort((a, b) => {
                    const aTime = a.start.dateTime || a.start.date || '';
                    const bTime = b.start.dateTime || b.start.date || '';
                    return aTime.localeCompare(bTime);
                });
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                events: allEvents.map(e => ({
                                    id: e.id,
                                    calendarId: e.calendarId,
                                    summary: e.summary,
                                    description: e.description,
                                    location: e.location,
                                    start: e.start,
                                    end: e.end,
                                    status: e.status,
                                    htmlLink: e.htmlLink,
                                    attendees: e.attendees?.length,
                                    accountEmail: e.accountEmail,
                                })),
                                totalEvents: allEvents.length,
                                accountsQueried: connections.map(c => c.email),
                            }, null, 2),
                        }],
                };
            }
            case 'calendar_get_event': {
                const params = GetEventSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                let event = null;
                for (const conn of connections) {
                    try {
                        const client = new CalendarClient(conn);
                        event = await client.getEvent(params.eventId, params.calendarId);
                        if (event)
                            break;
                    }
                    catch (e) {
                        // Continue to next account
                    }
                }
                if (!event) {
                    return {
                        content: [{
                                type: 'text',
                                text: JSON.stringify({
                                    success: false,
                                    error: `Event ${params.eventId} not found in any connected account`,
                                }, null, 2),
                            }],
                    };
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                event,
                            }, null, 2),
                        }],
                };
            }
            case 'calendar_create_event': {
                const params = CreateEventSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                if (connections.length === 0) {
                    throw new McpError(ErrorCode.InvalidRequest, params.accountEmail
                        ? `No account matches "${params.accountEmail}"`
                        : 'No connected accounts available');
                }
                const conn = connections[0];
                const client = new CalendarClient(conn);
                const event = await client.createEvent({
                    calendarId: params.calendarId,
                    summary: params.summary,
                    description: params.description,
                    location: params.location,
                    start: params.start,
                    end: params.end,
                    attendees: params.attendees,
                    sendUpdates: params.sendUpdates,
                    timeZone: params.timeZone,
                    colorId: params.colorId,
                });
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                message: 'Event created successfully',
                                event: {
                                    id: event.id,
                                    summary: event.summary,
                                    start: event.start,
                                    end: event.end,
                                    htmlLink: event.htmlLink,
                                    accountEmail: event.accountEmail,
                                },
                            }, null, 2),
                        }],
                };
            }
            case 'calendar_update_event': {
                const params = UpdateEventSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                let updatedEvent = null;
                let foundInAccount = null;
                for (const conn of connections) {
                    try {
                        const client = new CalendarClient(conn);
                        // First check if event exists in this account
                        const existing = await client.getEvent(params.eventId, params.calendarId);
                        if (existing) {
                            updatedEvent = await client.updateEvent({
                                eventId: params.eventId,
                                calendarId: params.calendarId,
                                summary: params.summary,
                                description: params.description,
                                location: params.location,
                                start: params.start,
                                end: params.end,
                                attendees: params.attendees,
                                sendUpdates: params.sendUpdates,
                                colorId: params.colorId,
                            });
                            foundInAccount = conn.email;
                            break;
                        }
                    }
                    catch (e) {
                        // Continue to next account
                    }
                }
                if (!updatedEvent) {
                    return {
                        content: [{
                                type: 'text',
                                text: JSON.stringify({
                                    success: false,
                                    error: `Event ${params.eventId} not found in any connected account`,
                                }, null, 2),
                            }],
                    };
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                message: 'Event updated successfully',
                                event: {
                                    id: updatedEvent.id,
                                    summary: updatedEvent.summary,
                                    start: updatedEvent.start,
                                    end: updatedEvent.end,
                                    htmlLink: updatedEvent.htmlLink,
                                    accountEmail: updatedEvent.accountEmail,
                                },
                            }, null, 2),
                        }],
                };
            }
            case 'calendar_delete_event': {
                const params = DeleteEventSchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                let deleted = false;
                let deletedFromAccount = null;
                for (const conn of connections) {
                    try {
                        const client = new CalendarClient(conn);
                        // First check if event exists
                        const existing = await client.getEvent(params.eventId, params.calendarId);
                        if (existing) {
                            await client.deleteEvent({
                                eventId: params.eventId,
                                calendarId: params.calendarId,
                                sendUpdates: params.sendUpdates,
                            });
                            deleted = true;
                            deletedFromAccount = conn.email;
                            break;
                        }
                    }
                    catch (e) {
                        // Continue to next account
                    }
                }
                if (!deleted) {
                    return {
                        content: [{
                                type: 'text',
                                text: JSON.stringify({
                                    success: false,
                                    error: `Event ${params.eventId} not found in any connected account`,
                                }, null, 2),
                            }],
                    };
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                message: 'Event deleted successfully',
                                eventId: params.eventId,
                                deletedFromAccount,
                            }, null, 2),
                        }],
                };
            }
            case 'calendar_free_busy': {
                const params = FreeBusySchema.parse(args);
                let connections = ensureConnections();
                connections = filterConnectionsByEmail(connections, params.accountEmail);
                const allResults = [];
                for (const conn of connections) {
                    try {
                        const client = new CalendarClient(conn);
                        const results = await client.getFreeBusy({
                            timeMin: params.timeMin,
                            timeMax: params.timeMax,
                            calendarIds: params.calendarIds,
                        });
                        allResults.push(...results);
                    }
                    catch (e) {
                        console.error(`Error checking free/busy for ${conn.email}:`, e.message);
                    }
                }
                return {
                    content: [{
                            type: 'text',
                            text: JSON.stringify({
                                success: true,
                                timeRange: {
                                    start: params.timeMin,
                                    end: params.timeMax,
                                },
                                results: allResults,
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
            throw new McpError(ErrorCode.InvalidRequest, 'Insufficient Calendar permissions. Please reconnect with the required scopes.');
        }
        throw new McpError(ErrorCode.InternalError, `Calendar operation failed: ${errorMessage}`);
    }
});
// Start server
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error('Google Calendar MCP server running on stdio');
}
main().catch((error) => {
    console.error('Server error:', error);
    process.exit(1);
});
//# sourceMappingURL=index.js.map