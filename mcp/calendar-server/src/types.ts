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
  email: string;           // Account email for identification/filtering
  access_token: string;    // OAuth access token
  refresh_token: string;   // OAuth refresh token
  expires_at: string;      // ISO8601 expiration timestamp
}

/**
 * Common filter parameter for multi-account operations.
 */
export interface AccountFilter {
  accountEmail?: string;   // Filter by account email (partial match, case-insensitive)
}

/**
 * Calendar info.
 */
export interface CalendarInfo {
  id: string;
  summary: string;         // Calendar name
  description?: string;
  timeZone: string;
  isPrimary: boolean;
  accessRole: string;      // owner, writer, reader
  backgroundColor?: string;
  foregroundColor?: string;
  accountEmail: string;
}

/**
 * Event date/time. Either dateTime (for timed events) or date (for all-day events).
 */
export interface EventDateTime {
  dateTime?: string;       // ISO8601 for timed events (e.g., "2025-01-10T10:00:00-05:00")
  date?: string;           // YYYY-MM-DD for all-day events
  timeZone?: string;       // e.g., "America/New_York"
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
  summary: string;         // Event title
  description?: string;
  location?: string;
  start: EventDateTime;
  end: EventDateTime;
  status: 'confirmed' | 'tentative' | 'cancelled';
  attendees?: EventAttendee[];
  organizer?: EventAttendee;
  htmlLink: string;        // Link to view in Google Calendar
  created: string;
  updated: string;
  recurringEventId?: string;
  recurrence?: string[];   // RRULE, EXRULE, etc.
  colorId?: string;
  accountEmail: string;
}

/**
 * Free/busy time slot.
 */
export interface FreeBusySlot {
  start: string;           // ISO8601
  end: string;             // ISO8601
}

/**
 * Free/busy result for a calendar.
 */
export interface FreeBusyResult {
  calendarId: string;
  busy: FreeBusySlot[];
  accountEmail: string;
}

// ============ Parameter Types ============

/**
 * List calendars parameters.
 */
export interface ListCalendarsParams extends AccountFilter {
  // No additional params
}

/**
 * List events parameters.
 */
export interface ListEventsParams extends AccountFilter {
  calendarId?: string;     // Default 'primary'
  timeMin?: string;        // ISO8601, default now
  timeMax?: string;        // ISO8601, default +7 days
  maxResults?: number;     // Default 50
  singleEvents?: boolean;  // Expand recurring events, default true
  orderBy?: 'startTime' | 'updated';
  q?: string;              // Search query
}

/**
 * Get event parameters.
 */
export interface GetEventParams extends AccountFilter {
  eventId: string;
  calendarId?: string;     // Default 'primary'
}

/**
 * Create event parameters.
 */
export interface CreateEventParams extends AccountFilter {
  calendarId?: string;     // Default 'primary'
  summary: string;
  description?: string;
  location?: string;
  start: EventDateTime;
  end: EventDateTime;
  attendees?: string[];    // Email addresses
  sendUpdates?: 'all' | 'externalOnly' | 'none'; // Default 'all'
  timeZone?: string;       // Default to account's calendar timezone
  colorId?: string;
}

/**
 * Update event parameters.
 */
export interface UpdateEventParams extends AccountFilter {
  eventId: string;
  calendarId?: string;     // Default 'primary'
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
  calendarId?: string;     // Default 'primary'
  sendUpdates?: 'all' | 'externalOnly' | 'none';
}

/**
 * Free/busy query parameters.
 */
export interface FreeBusyParams extends AccountFilter {
  timeMin: string;         // ISO8601
  timeMax: string;         // ISO8601
  calendarIds?: string[];  // Default ['primary']
}
