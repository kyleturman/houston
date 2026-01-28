/**
 * Google Calendar API Client
 *
 * Wraps Google Calendar API with typed methods for common operations.
 * Handles date/time formatting and event management.
 */

import { google, calendar_v3 } from 'googleapis';
import {
  GoogleConnection,
  CalendarInfo,
  CalendarEvent,
  EventDateTime,
  EventAttendee,
  FreeBusyResult,
  FreeBusySlot,
} from './types.js';

/**
 * Calendar client for a single Google account.
 */
export class CalendarClient {
  private calendar: calendar_v3.Calendar;
  private accountEmail: string;

  constructor(connection: GoogleConnection) {
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
  async listCalendars(): Promise<CalendarInfo[]> {
    const response = await this.calendar.calendarList.list({
      maxResults: 100,
    });

    return (response.data.items || []).map(cal => ({
      id: cal.id!,
      summary: cal.summary || 'Untitled',
      description: cal.description ?? undefined,
      timeZone: cal.timeZone || 'UTC',
      isPrimary: cal.primary || false,
      accessRole: cal.accessRole || 'reader',
      backgroundColor: cal.backgroundColor ?? undefined,
      foregroundColor: cal.foregroundColor ?? undefined,
      accountEmail: this.accountEmail,
    }));
  }

  /**
   * List events in a calendar within a time range.
   */
  async listEvents(params: {
    calendarId?: string;
    timeMin?: string;
    timeMax?: string;
    maxResults?: number;
    singleEvents?: boolean;
    orderBy?: 'startTime' | 'updated';
    q?: string;
  }): Promise<CalendarEvent[]> {
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
  async getEvent(eventId: string, calendarId: string = 'primary'): Promise<CalendarEvent | null> {
    try {
      const response = await this.calendar.events.get({
        calendarId,
        eventId,
      });

      return this.parseEvent(response.data, calendarId);
    } catch (error: any) {
      if (error.code === 404) {
        return null;
      }
      throw error;
    }
  }

  /**
   * Create a new event.
   */
  async createEvent(params: {
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
  }): Promise<CalendarEvent> {
    const calendarId = params.calendarId || 'primary';

    const eventBody: calendar_v3.Schema$Event = {
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
  async updateEvent(params: {
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
  }): Promise<CalendarEvent> {
    const calendarId = params.calendarId || 'primary';

    // First get the existing event
    const existing = await this.getEvent(params.eventId, calendarId);
    if (!existing) {
      throw new Error(`Event ${params.eventId} not found`);
    }

    const eventBody: calendar_v3.Schema$Event = {};

    if (params.summary !== undefined) eventBody.summary = params.summary;
    if (params.description !== undefined) eventBody.description = params.description;
    if (params.location !== undefined) eventBody.location = params.location;
    if (params.colorId !== undefined) eventBody.colorId = params.colorId;

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
  async deleteEvent(params: {
    eventId: string;
    calendarId?: string;
    sendUpdates?: 'all' | 'externalOnly' | 'none';
  }): Promise<void> {
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
  async getFreeBusy(params: {
    timeMin: string;
    timeMax: string;
    calendarIds?: string[];
  }): Promise<FreeBusyResult[]> {
    const calendarIds = params.calendarIds || ['primary'];

    const response = await this.calendar.freebusy.query({
      requestBody: {
        timeMin: params.timeMin,
        timeMax: params.timeMax,
        items: calendarIds.map(id => ({ id })),
      },
    });

    const calendars = response.data.calendars || {};
    const results: FreeBusyResult[] = [];

    for (const calendarId of calendarIds) {
      const calData = calendars[calendarId];
      if (calData) {
        results.push({
          calendarId,
          busy: (calData.busy || []).map(slot => ({
            start: slot.start!,
            end: slot.end!,
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
  private parseEvent(event: calendar_v3.Schema$Event, calendarId: string): CalendarEvent {
    return {
      id: event.id!,
      calendarId,
      summary: event.summary || 'Untitled',
      description: event.description ?? undefined,
      location: event.location ?? undefined,
      start: this.parseEventDateTime(event.start),
      end: this.parseEventDateTime(event.end),
      status: (event.status as 'confirmed' | 'tentative' | 'cancelled') || 'confirmed',
      attendees: event.attendees?.map(att => ({
        email: att.email!,
        displayName: att.displayName ?? undefined,
        responseStatus: att.responseStatus as EventAttendee['responseStatus'],
        organizer: att.organizer ?? undefined,
        self: att.self ?? undefined,
        optional: att.optional ?? undefined,
      })),
      organizer: event.organizer ? {
        email: event.organizer.email!,
        displayName: event.organizer.displayName ?? undefined,
        organizer: true,
        self: event.organizer.self ?? undefined,
      } : undefined,
      htmlLink: event.htmlLink || '',
      created: event.created || '',
      updated: event.updated || '',
      recurringEventId: event.recurringEventId ?? undefined,
      recurrence: event.recurrence ?? undefined,
      colorId: event.colorId ?? undefined,
      accountEmail: this.accountEmail,
    };
  }

  /**
   * Parse event date/time from Google API format.
   */
  private parseEventDateTime(dt?: calendar_v3.Schema$EventDateTime): EventDateTime {
    if (!dt) {
      return { dateTime: new Date().toISOString() };
    }

    return {
      dateTime: dt.dateTime ?? undefined,
      date: dt.date ?? undefined,
      timeZone: dt.timeZone ?? undefined,
    };
  }

  /**
   * Format EventDateTime for Google API.
   */
  private formatEventDateTime(dt: EventDateTime, timeZone?: string): calendar_v3.Schema$EventDateTime {
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
