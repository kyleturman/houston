/**
 * Google Calendar MCP Server Types
 *
 * Defines interfaces for multi-account Google connections and Calendar data structures.
 */
/**
 * Google connection structure passed via GOOGLE_CONNECTIONS environment variable.
 * Each connection represents a user's authenticated Google account.
 */
export interface GoogleConnection {
    email: string;
    access_token: string;
    refresh_token: string;
    expires_at: string;
}
/**
 * Common filter parameter for multi-account operations.
 */
export interface AccountFilter {
    accountEmail?: string;
}
/**
 * Calendar info.
 */
export interface CalendarInfo {
    id: string;
    summary: string;
    description?: string;
    timeZone: string;
    isPrimary: boolean;
    accessRole: string;
    backgroundColor?: string;
    foregroundColor?: string;
    accountEmail: string;
}
/**
 * Event date/time. Either dateTime (for timed events) or date (for all-day events).
 */
export interface EventDateTime {
    dateTime?: string;
    date?: string;
    timeZone?: string;
}
/**
 * Event attendee.
 */
export interface EventAttendee {
    email: string;
    displayName?: string;
    responseStatus?: 'needsAction' | 'declined' | 'tentative' | 'accepted';
    organizer?: boolean;
    self?: boolean;
    optional?: boolean;
}
/**
 * Calendar event.
 */
export interface CalendarEvent {
    id: string;
    calendarId: string;
    summary: string;
    description?: string;
    location?: string;
    start: EventDateTime;
    end: EventDateTime;
    status: 'confirmed' | 'tentative' | 'cancelled';
    attendees?: EventAttendee[];
    organizer?: EventAttendee;
    htmlLink: string;
    created: string;
    updated: string;
    recurringEventId?: string;
    recurrence?: string[];
    colorId?: string;
    accountEmail: string;
}
/**
 * Free/busy time slot.
 */
export interface FreeBusySlot {
    start: string;
    end: string;
}
/**
 * Free/busy result for a calendar.
 */
export interface FreeBusyResult {
    calendarId: string;
    busy: FreeBusySlot[];
    accountEmail: string;
}
/**
 * List calendars parameters.
 */
export interface ListCalendarsParams extends AccountFilter {
}
/**
 * List events parameters.
 */
export interface ListEventsParams extends AccountFilter {
    calendarId?: string;
    timeMin?: string;
    timeMax?: string;
    maxResults?: number;
    singleEvents?: boolean;
    orderBy?: 'startTime' | 'updated';
    q?: string;
}
/**
 * Get event parameters.
 */
export interface GetEventParams extends AccountFilter {
    eventId: string;
    calendarId?: string;
}
/**
 * Create event parameters.
 */
export interface CreateEventParams extends AccountFilter {
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
}
/**
 * Update event parameters.
 */
export interface UpdateEventParams extends AccountFilter {
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
}
/**
 * Delete event parameters.
 */
export interface DeleteEventParams extends AccountFilter {
    eventId: string;
    calendarId?: string;
    sendUpdates?: 'all' | 'externalOnly' | 'none';
}
/**
 * Free/busy query parameters.
 */
export interface FreeBusyParams extends AccountFilter {
    timeMin: string;
    timeMax: string;
    calendarIds?: string[];
}
//# sourceMappingURL=types.d.ts.map