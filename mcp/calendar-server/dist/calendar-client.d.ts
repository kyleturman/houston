/**
 * Google Calendar API Client
 *
 * Wraps Google Calendar API with typed methods for common operations.
 * Handles date/time formatting and event management.
 */
import { GoogleConnection, CalendarInfo, CalendarEvent, EventDateTime, FreeBusyResult } from './types.js';
/**
 * Calendar client for a single Google account.
 */
export declare class CalendarClient {
    private calendar;
    private accountEmail;
    constructor(connection: GoogleConnection);
    /**
     * List all calendars for this account.
     */
    listCalendars(): Promise<CalendarInfo[]>;
    /**
     * List events in a calendar within a time range.
     */
    listEvents(params: {
        calendarId?: string;
        timeMin?: string;
        timeMax?: string;
        maxResults?: number;
        singleEvents?: boolean;
        orderBy?: 'startTime' | 'updated';
        q?: string;
    }): Promise<CalendarEvent[]>;
    /**
     * Get a single event by ID.
     */
    getEvent(eventId: string, calendarId?: string): Promise<CalendarEvent | null>;
    /**
     * Create a new event.
     */
    createEvent(params: {
        calendarId?: string;
        summary: string;
        description?: string;
        location?: string;
        start: EventDateTime;
        end: EventDateTime;
        attendees?: string[];
        sendUpdates?: 'all' | 'externalOnly' | 'none';
        timeZone?: string;
        colorId?: string;
    }): Promise<CalendarEvent>;
    /**
     * Update an existing event.
     */
    updateEvent(params: {
        eventId: string;
        calendarId?: string;
        summary?: string;
        description?: string;
        location?: string;
        start?: EventDateTime;
        end?: EventDateTime;
        attendees?: string[];
        sendUpdates?: 'all' | 'externalOnly' | 'none';
        colorId?: string;
    }): Promise<CalendarEvent>;
    /**
     * Delete an event.
     */
    deleteEvent(params: {
        eventId: string;
        calendarId?: string;
        sendUpdates?: 'all' | 'externalOnly' | 'none';
    }): Promise<void>;
    /**
     * Query free/busy information.
     */
    getFreeBusy(params: {
        timeMin: string;
        timeMax: string;
        calendarIds?: string[];
    }): Promise<FreeBusyResult[]>;
    /**
     * Parse a Google Calendar API event into our CalendarEvent type.
     */
    private parseEvent;
    /**
     * Parse event date/time from Google API format.
     */
    private parseEventDateTime;
    /**
     * Format EventDateTime for Google API.
     */
    private formatEventDateTime;
}
//# sourceMappingURL=calendar-client.d.ts.map