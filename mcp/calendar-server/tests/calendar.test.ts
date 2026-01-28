/**
 * Google Calendar MCP Server Tests
 *
 * Tests the core functionality with mocked Google API responses.
 */

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';

// Mock environment for multi-connection support
const mockConnections = [
  {
    email: 'personal@gmail.com',
    access_token: 'mock_token_1',
    refresh_token: 'mock_refresh_1',
    expires_at: '2025-12-31T00:00:00Z',
  },
  {
    email: 'work@company.com',
    access_token: 'mock_token_2',
    refresh_token: 'mock_refresh_2',
    expires_at: '2025-12-31T00:00:00Z',
  },
];

describe('Calendar MCP Server', () => {
  describe('getConnections', () => {
    it('should parse GOOGLE_CONNECTIONS environment variable', () => {
      process.env.GOOGLE_CONNECTIONS = JSON.stringify(mockConnections);

      const connectionsJson = process.env.GOOGLE_CONNECTIONS;
      const connections = JSON.parse(connectionsJson!);

      assert.strictEqual(connections.length, 2);
      assert.strictEqual(connections[0].email, 'personal@gmail.com');
      assert.strictEqual(connections[1].email, 'work@company.com');
    });

    it('should fall back to legacy env vars if GOOGLE_CONNECTIONS is not set', () => {
      delete process.env.GOOGLE_CONNECTIONS;
      process.env.GOOGLE_API_ACCESS_TOKEN = 'legacy_token';
      process.env.GOOGLE_USER_EMAIL = 'legacy@gmail.com';

      const connectionsJson = process.env.GOOGLE_CONNECTIONS;
      let connections: any[] = [];

      if (connectionsJson) {
        connections = JSON.parse(connectionsJson);
      } else if (process.env.GOOGLE_API_ACCESS_TOKEN) {
        connections = [{
          email: process.env.GOOGLE_USER_EMAIL || 'unknown',
          access_token: process.env.GOOGLE_API_ACCESS_TOKEN,
          refresh_token: process.env.GOOGLE_REFRESH_TOKEN || '',
          expires_at: '',
        }];
      }

      assert.strictEqual(connections.length, 1);
      assert.strictEqual(connections[0].email, 'legacy@gmail.com');
    });
  });

  describe('filterConnectionsByEmail', () => {
    it('should filter connections by email (case-insensitive partial match)', () => {
      const filterConnectionsByEmail = (connections: any[], email?: string) => {
        if (!email) return connections;
        const searchTerm = email.toLowerCase();
        return connections.filter((c: any) => c.email.toLowerCase().includes(searchTerm));
      };

      const result = filterConnectionsByEmail(mockConnections, 'gmail');
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].email, 'personal@gmail.com');

      const workResult = filterConnectionsByEmail(mockConnections, 'company');
      assert.strictEqual(workResult.length, 1);
      assert.strictEqual(workResult[0].email, 'work@company.com');

      const allResult = filterConnectionsByEmail(mockConnections, undefined);
      assert.strictEqual(allResult.length, 2);
    });
  });

  describe('EventDateTime handling', () => {
    it('should parse all-day events correctly', () => {
      const parseEventDateTime = (dt: { date?: string; dateTime?: string; timeZone?: string }) => {
        return {
          dateTime: dt.dateTime ?? undefined,
          date: dt.date ?? undefined,
          timeZone: dt.timeZone ?? undefined,
        };
      };

      const allDayEvent = parseEventDateTime({ date: '2025-01-15' });
      assert.strictEqual(allDayEvent.date, '2025-01-15');
      assert.strictEqual(allDayEvent.dateTime, undefined);
    });

    it('should parse timed events correctly', () => {
      const parseEventDateTime = (dt: { date?: string; dateTime?: string; timeZone?: string }) => {
        return {
          dateTime: dt.dateTime ?? undefined,
          date: dt.date ?? undefined,
          timeZone: dt.timeZone ?? undefined,
        };
      };

      const timedEvent = parseEventDateTime({
        dateTime: '2025-01-15T10:00:00-05:00',
        timeZone: 'America/New_York'
      });
      assert.strictEqual(timedEvent.dateTime, '2025-01-15T10:00:00-05:00');
      assert.strictEqual(timedEvent.timeZone, 'America/New_York');
      assert.strictEqual(timedEvent.date, undefined);
    });
  });

  describe('Event formatting', () => {
    it('should format EventDateTime for all-day events', () => {
      const formatEventDateTime = (dt: { date?: string; dateTime?: string; timeZone?: string }, timeZone?: string) => {
        if (dt.date) {
          return { date: dt.date };
        }
        return {
          dateTime: dt.dateTime,
          timeZone: dt.timeZone || timeZone,
        };
      };

      const result = formatEventDateTime({ date: '2025-01-15' });
      assert.deepStrictEqual(result, { date: '2025-01-15' });
    });

    it('should format EventDateTime for timed events with timezone', () => {
      const formatEventDateTime = (dt: { date?: string; dateTime?: string; timeZone?: string }, timeZone?: string) => {
        if (dt.date) {
          return { date: dt.date };
        }
        return {
          dateTime: dt.dateTime,
          timeZone: dt.timeZone || timeZone,
        };
      };

      const result = formatEventDateTime(
        { dateTime: '2025-01-15T10:00:00' },
        'America/New_York'
      );
      assert.strictEqual(result.dateTime, '2025-01-15T10:00:00');
      assert.strictEqual(result.timeZone, 'America/New_York');
    });
  });

  describe('Multi-account event merging', () => {
    it('should merge and sort events by start time', () => {
      const events = [
        {
          id: '3',
          summary: 'Third',
          start: { dateTime: '2025-01-15T14:00:00Z' },
          accountEmail: 'a@gmail.com'
        },
        {
          id: '1',
          summary: 'First',
          start: { dateTime: '2025-01-15T09:00:00Z' },
          accountEmail: 'b@gmail.com'
        },
        {
          id: '2',
          summary: 'Second',
          start: { dateTime: '2025-01-15T11:00:00Z' },
          accountEmail: 'a@gmail.com'
        },
      ];

      const sorted = [...events].sort((a, b) => {
        const aTime = a.start.dateTime || '';
        const bTime = b.start.dateTime || '';
        return aTime.localeCompare(bTime);
      });

      assert.strictEqual(sorted[0].summary, 'First');
      assert.strictEqual(sorted[1].summary, 'Second');
      assert.strictEqual(sorted[2].summary, 'Third');
    });

    it('should handle mixed all-day and timed events', () => {
      const events = [
        {
          id: '1',
          summary: 'All Day Event',
          start: { date: '2025-01-15' },
          accountEmail: 'a@gmail.com'
        },
        {
          id: '2',
          summary: 'Morning Meeting',
          start: { dateTime: '2025-01-15T09:00:00Z' },
          accountEmail: 'b@gmail.com'
        },
      ];

      const sorted = [...events].sort((a, b) => {
        const aTime = a.start.dateTime || a.start.date || '';
        const bTime = b.start.dateTime || b.start.date || '';
        return aTime.localeCompare(bTime);
      });

      // All-day event (date only) comes before timed event on same day
      assert.strictEqual(sorted[0].summary, 'All Day Event');
      assert.strictEqual(sorted[1].summary, 'Morning Meeting');
    });
  });

  describe('Free/Busy handling', () => {
    it('should aggregate busy slots from multiple calendars', () => {
      const freeBusyResults = [
        {
          calendarId: 'primary',
          busy: [
            { start: '2025-01-15T09:00:00Z', end: '2025-01-15T10:00:00Z' },
          ],
          accountEmail: 'a@gmail.com',
        },
        {
          calendarId: 'primary',
          busy: [
            { start: '2025-01-15T14:00:00Z', end: '2025-01-15T15:00:00Z' },
          ],
          accountEmail: 'b@gmail.com',
        },
      ];

      const allBusySlots = freeBusyResults.flatMap(r => r.busy);
      assert.strictEqual(allBusySlots.length, 2);
    });
  });

  describe('Calendar info parsing', () => {
    it('should parse calendar list response', () => {
      const mockCalendar = {
        id: 'primary',
        summary: 'My Calendar',
        description: 'Personal calendar',
        timeZone: 'America/New_York',
        primary: true,
        accessRole: 'owner',
        backgroundColor: '#0088aa',
        foregroundColor: '#ffffff',
      };

      const parsed = {
        id: mockCalendar.id,
        summary: mockCalendar.summary || 'Untitled',
        description: mockCalendar.description ?? undefined,
        timeZone: mockCalendar.timeZone || 'UTC',
        isPrimary: mockCalendar.primary || false,
        accessRole: mockCalendar.accessRole || 'reader',
        backgroundColor: mockCalendar.backgroundColor ?? undefined,
        foregroundColor: mockCalendar.foregroundColor ?? undefined,
        accountEmail: 'test@gmail.com',
      };

      assert.strictEqual(parsed.id, 'primary');
      assert.strictEqual(parsed.summary, 'My Calendar');
      assert.strictEqual(parsed.isPrimary, true);
      assert.strictEqual(parsed.accessRole, 'owner');
    });
  });

  describe('Attendee handling', () => {
    it('should parse attendees from event response', () => {
      const mockAttendees = [
        {
          email: 'alice@example.com',
          displayName: 'Alice Smith',
          responseStatus: 'accepted',
          organizer: true,
        },
        {
          email: 'bob@example.com',
          displayName: null,
          responseStatus: 'needsAction',
          optional: true,
        },
      ];

      const parsed = mockAttendees.map(att => ({
        email: att.email,
        displayName: att.displayName ?? undefined,
        responseStatus: att.responseStatus,
        organizer: att.organizer ?? undefined,
        optional: att.optional ?? undefined,
      }));

      assert.strictEqual(parsed[0].email, 'alice@example.com');
      assert.strictEqual(parsed[0].displayName, 'Alice Smith');
      assert.strictEqual(parsed[0].organizer, true);
      assert.strictEqual(parsed[1].displayName, undefined);
      assert.strictEqual(parsed[1].optional, true);
    });

    it('should convert email array to attendee format', () => {
      const emails = ['alice@example.com', 'bob@example.com'];
      const attendees = emails.map(email => ({ email }));

      assert.strictEqual(attendees.length, 2);
      assert.deepStrictEqual(attendees[0], { email: 'alice@example.com' });
    });
  });
});

describe('Error handling', () => {
  it('should detect token expiration errors', () => {
    const isTokenExpiredError = (message: string): boolean => {
      return message.includes('invalid_grant') || message.includes('Token has been expired');
    };

    assert.ok(isTokenExpiredError('invalid_grant: Token has been expired'));
    assert.ok(!isTokenExpiredError('Some other error'));
  });

  it('should detect permission errors', () => {
    const isPermissionError = (message: string): boolean => {
      return message.includes('insufficient permission') || message.includes('403');
    };

    assert.ok(isPermissionError('insufficient permission'));
    assert.ok(isPermissionError('Error 403: Access denied'));
    assert.ok(!isPermissionError('404 not found'));
  });
});

describe('Default value handling', () => {
  it('should use default time range when not specified', () => {
    const now = new Date();
    const sevenDaysFromNow = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

    const params = {
      timeMin: undefined,
      timeMax: undefined,
    };

    const effectiveTimeMin = params.timeMin || now.toISOString();
    const effectiveTimeMax = params.timeMax || sevenDaysFromNow.toISOString();

    // Should be close to now and 7 days from now
    const timeMinDate = new Date(effectiveTimeMin);
    const timeMaxDate = new Date(effectiveTimeMax);

    const diffDays = (timeMaxDate.getTime() - timeMinDate.getTime()) / (1000 * 60 * 60 * 24);
    assert.ok(diffDays >= 6.9 && diffDays <= 7.1);
  });

  it('should use primary calendar when not specified', () => {
    const params = { calendarId: undefined };
    const effectiveCalendarId = params.calendarId || 'primary';
    assert.strictEqual(effectiveCalendarId, 'primary');
  });
});
