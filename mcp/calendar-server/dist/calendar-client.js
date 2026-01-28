/**
 * Google Calendar API Client
 *
 * Wraps Google Calendar API with typed methods for common operations.
 * Handles date/time formatting and event management.
 */
import { google } from 'googleapis';
/**
 * Calendar client for a single Google account.
 */
export class CalendarClient {
    calendar;
    accountEmail;
    constructor(connection) {
        const auth = new google.auth.OAuth2();
        auth.setCredentials({
            access_token: connection.access_token,
            refresh_token: connection.refresh_token,
        });
        this.calendar = google.calendar({ version: 'v3', auth });
        this.accountEmail = connection.email;
    }
    /**
     * List all calendars for this account.
     */
    async listCalendars() {
        const response = await this.calendar.calendarList.list({
            maxResults: 100,
        });
        return (response.data.items || []).map(cal => ({
            id: cal.id,
            summary: cal.summary || 'Untitled',
            description: cal.description,
            timeZone: cal.timeZone || 'UTC',
            isPrimary: cal.primary || false,
            accessRole: cal.accessRole || 'reader',
            backgroundColor: cal.backgroundColor,
            foregroundColor: cal.foregroundColor,
            accountEmail: this.accountEmail,
        }));
    }
    /**
     * List events in a calendar within a time range.
     */
    async listEvents(params) {
        const calendarId = params.calendarId || 'primary';
        // Default time range: now to 7 days from now
        const now = new Date();
        const sevenDaysFromNow = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
        const response = await this.calendar.events.list({
            calendarId,
            timeMin: params.timeMin || now.toISOString(),
            timeMax: params.timeMax || sevenDaysFromNow.toISOString(),
            maxResults: params.maxResults || 50,
            singleEvents: params.singleEvents !== false, // Default true
            orderBy: params.singleEvents !== false ? (params.orderBy || 'startTime') : undefined,
            q: params.q,
        });
        return (response.data.items || []).map(event => this.parseEvent(event, calendarId));
    }
    /**
     * Get a single event by ID.
     */
    async getEvent(eventId, calendarId = 'primary') {
        try {
            const response = await this.calendar.events.get({
                calendarId,
                eventId,
            });
            return this.parseEvent(response.data, calendarId);
        }
        catch (error) {
            if (error.code === 404) {
                return null;
            }
            throw error;
        }
    }
    /**
     * Create a new event.
     */
    async createEvent(params) {
        const calendarId = params.calendarId || 'primary';
        const eventBody = {
            summary: params.summary,
            description: params.description,
            location: params.location,
            start: this.formatEventDateTime(params.start, params.timeZone),
            end: this.formatEventDateTime(params.end, params.timeZone),
            colorId: params.colorId,
        };
        if (params.attendees && params.attendees.length > 0) {
            eventBody.attendees = params.attendees.map(email => ({ email }));
        }
        const response = await this.calendar.events.insert({
            calendarId,
            requestBody: eventBody,
            sendUpdates: params.sendUpdates || 'all',
        });
        return this.parseEvent(response.data, calendarId);
    }
    /**
     * Update an existing event.
     */
    async updateEvent(params) {
        const calendarId = params.calendarId || 'primary';
        // First get the existing event
        const existing = await this.getEvent(params.eventId, calendarId);
        if (!existing) {
            throw new Error(`Event ${params.eventId} not found`);
        }
        const eventBody = {};
        if (params.summary !== undefined)
            eventBody.summary = params.summary;
        if (params.description !== undefined)
            eventBody.description = params.description;
        if (params.location !== undefined)
            eventBody.location = params.location;
        if (params.colorId !== undefined)
            eventBody.colorId = params.colorId;
        if (params.start) {
            eventBody.start = this.formatEventDateTime(params.start);
        }
        if (params.end) {
            eventBody.end = this.formatEventDateTime(params.end);
        }
        if (params.attendees !== undefined) {
            eventBody.attendees = params.attendees.map(email => ({ email }));
        }
        const response = await this.calendar.events.patch({
            calendarId,
            eventId: params.eventId,
            requestBody: eventBody,
            sendUpdates: params.sendUpdates || 'all',
        });
        return this.parseEvent(response.data, calendarId);
    }
    /**
     * Delete an event.
     */
    async deleteEvent(params) {
        const calendarId = params.calendarId || 'primary';
        await this.calendar.events.delete({
            calendarId,
            eventId: params.eventId,
            sendUpdates: params.sendUpdates || 'all',
        });
    }
    /**
     * Query free/busy information.
     */
    async getFreeBusy(params) {
        const calendarIds = params.calendarIds || ['primary'];
        const response = await this.calendar.freebusy.query({
            requestBody: {
                timeMin: params.timeMin,
                timeMax: params.timeMax,
                items: calendarIds.map(id => ({ id })),
            },
        });
        const calendars = response.data.calendars || {};
        const results = [];
        for (const calendarId of calendarIds) {
            const calData = calendars[calendarId];
            if (calData) {
                results.push({
                    calendarId,
                    busy: (calData.busy || []).map(slot => ({
                        start: slot.start,
                        end: slot.end,
                    })),
                    accountEmail: this.accountEmail,
                });
            }
        }
        return results;
    }
    /**
     * Parse a Google Calendar API event into our CalendarEvent type.
     */
    parseEvent(event, calendarId) {
        return {
            id: event.id,
            calendarId,
            summary: event.summary || 'Untitled',
            description: event.description,
            location: event.location,
            start: this.parseEventDateTime(event.start),
            end: this.parseEventDateTime(event.end),
            status: event.status || 'confirmed',
            attendees: event.attendees?.map(att => ({
                email: att.email,
                displayName: att.displayName,
                responseStatus: att.responseStatus,
                organizer: att.organizer,
                self: att.self,
                optional: att.optional,
            })),
            organizer: event.organizer ? {
                email: event.organizer.email,
                displayName: event.organizer.displayName,
                organizer: true,
                self: event.organizer.self,
            } : undefined,
            htmlLink: event.htmlLink || '',
            created: event.created || '',
            updated: event.updated || '',
            recurringEventId: event.recurringEventId,
            recurrence: event.recurrence,
            colorId: event.colorId,
            accountEmail: this.accountEmail,
        };
    }
    /**
     * Parse event date/time from Google API format.
     */
    parseEventDateTime(dt) {
        if (!dt) {
            return { dateTime: new Date().toISOString() };
        }
        return {
            dateTime: dt.dateTime,
            date: dt.date,
            timeZone: dt.timeZone,
        };
    }
    /**
     * Format EventDateTime for Google API.
     */
    formatEventDateTime(dt, timeZone) {
        if (dt.date) {
            // All-day event
            return { date: dt.date };
        }
        return {
            dateTime: dt.dateTime,
            timeZone: dt.timeZone || timeZone,
        };
    }
}
//# sourceMappingURL=calendar-client.js.map