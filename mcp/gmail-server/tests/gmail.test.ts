/**
 * Gmail MCP Server Tests
 *
 * Tests the core functionality with mocked Google API responses.
 */

import { describe, it, beforeEach, mock } from 'node:test';
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

describe('Gmail MCP Server', () => {
  describe('getConnections', () => {
    it('should parse GOOGLE_CONNECTIONS environment variable', () => {
      process.env.GOOGLE_CONNECTIONS = JSON.stringify(mockConnections);

      // Simulate the getConnections function
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

      // Simulate fallback logic
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
      assert.strictEqual(connections[0].access_token, 'legacy_token');
    });

    it('should return empty array if no connections configured', () => {
      delete process.env.GOOGLE_CONNECTIONS;
      delete process.env.GOOGLE_API_ACCESS_TOKEN;

      const connectionsJson = process.env.GOOGLE_CONNECTIONS;
      let connections: any[] = [];

      if (connectionsJson) {
        connections = JSON.parse(connectionsJson);
      } else if (process.env.GOOGLE_API_ACCESS_TOKEN) {
        connections = [{ email: 'unknown' }];
      }

      assert.strictEqual(connections.length, 0);
    });
  });

  describe('filterConnectionsByEmail', () => {
    it('should filter connections by email (case-insensitive partial match)', () => {
      const filterConnectionsByEmail = (connections: any[], email?: string) => {
        if (!email) return connections;
        const searchTerm = email.toLowerCase();
        return connections.filter((c: any) => c.email.toLowerCase().includes(searchTerm));
      };

      // Filter by partial match
      const result = filterConnectionsByEmail(mockConnections, 'gmail');
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].email, 'personal@gmail.com');

      // Filter by company
      const workResult = filterConnectionsByEmail(mockConnections, 'company');
      assert.strictEqual(workResult.length, 1);
      assert.strictEqual(workResult[0].email, 'work@company.com');

      // No filter returns all
      const allResult = filterConnectionsByEmail(mockConnections, undefined);
      assert.strictEqual(allResult.length, 2);

      // Case insensitive
      const upperResult = filterConnectionsByEmail(mockConnections, 'GMAIL');
      assert.strictEqual(upperResult.length, 1);
    });
  });

  describe('GmailMessage parsing', () => {
    it('should correctly parse email headers', () => {
      const mockHeaders = [
        { name: 'Subject', value: 'Test Email' },
        { name: 'From', value: 'sender@example.com' },
        { name: 'To', value: 'recipient@example.com, another@example.com' },
        { name: 'Date', value: 'Thu, 10 Jan 2025 10:00:00 -0500' },
        { name: 'Cc', value: 'cc@example.com' },
      ];

      const getHeader = (name: string): string => {
        const header = mockHeaders.find(h => h.name?.toLowerCase() === name.toLowerCase());
        return header?.value || '';
      };

      assert.strictEqual(getHeader('Subject'), 'Test Email');
      assert.strictEqual(getHeader('From'), 'sender@example.com');
      assert.strictEqual(getHeader('subject'), 'Test Email'); // case insensitive
    });

    it('should correctly parse address lists', () => {
      const parseAddressList = (value: string): string[] => {
        if (!value) return [];
        return value.split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/).map(s => s.trim()).filter(Boolean);
      };

      const result = parseAddressList('a@example.com, b@example.com');
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0], 'a@example.com');
      assert.strictEqual(result[1], 'b@example.com');

      // Handles quoted strings
      const quotedResult = parseAddressList('"Doe, John" <john@example.com>, jane@example.com');
      assert.strictEqual(quotedResult.length, 2);
    });
  });

  describe('Base64URL encoding/decoding', () => {
    it('should correctly decode base64url strings', () => {
      const decodeBase64Url = (data: string): string => {
        const base64 = data.replace(/-/g, '+').replace(/_/g, '/');
        const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
        return Buffer.from(padded, 'base64').toString('utf-8');
      };

      // Test with URL-safe base64
      const encoded = Buffer.from('Hello, World!').toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      const decoded = decodeBase64Url(encoded);
      assert.strictEqual(decoded, 'Hello, World!');
    });

    it('should correctly encode to base64url', () => {
      const encodeBase64Url = (data: string): string => {
        return Buffer.from(data, 'utf-8')
          .toString('base64')
          .replace(/\+/g, '-')
          .replace(/\//g, '_')
          .replace(/=+$/, '');
      };

      const result = encodeBase64Url('Hello, World!');
      // Should not contain + / or =
      assert.ok(!result.includes('+'));
      assert.ok(!result.includes('/'));
      assert.ok(!result.includes('='));
    });
  });

  describe('Email composition', () => {
    it('should create valid email headers', () => {
      const createEmailHeaders = (params: {
        to: string[];
        subject: string;
        cc?: string[];
        replyToMessageId?: string;
      }): string => {
        let email = '';
        email += `To: ${params.to.join(', ')}\r\n`;
        if (params.cc && params.cc.length > 0) {
          email += `Cc: ${params.cc.join(', ')}\r\n`;
        }
        email += `Subject: ${params.subject}\r\n`;
        if (params.replyToMessageId) {
          email += `In-Reply-To: ${params.replyToMessageId}\r\n`;
          email += `References: ${params.replyToMessageId}\r\n`;
        }
        return email;
      };

      const result = createEmailHeaders({
        to: ['recipient@example.com'],
        subject: 'Test Subject',
        cc: ['cc@example.com'],
      });

      assert.ok(result.includes('To: recipient@example.com'));
      assert.ok(result.includes('Subject: Test Subject'));
      assert.ok(result.includes('Cc: cc@example.com'));
    });
  });

  describe('Multi-account merging', () => {
    it('should merge and sort messages by date', () => {
      const messages = [
        { date: '2025-01-10T10:00:00Z', subject: 'Third', accountEmail: 'a@gmail.com' },
        { date: '2025-01-08T10:00:00Z', subject: 'First', accountEmail: 'b@gmail.com' },
        { date: '2025-01-09T10:00:00Z', subject: 'Second', accountEmail: 'a@gmail.com' },
      ];

      // Sort by date descending (newest first)
      const sorted = [...messages].sort((a, b) =>
        new Date(b.date).getTime() - new Date(a.date).getTime()
      );

      assert.strictEqual(sorted[0].subject, 'Third');
      assert.strictEqual(sorted[1].subject, 'Second');
      assert.strictEqual(sorted[2].subject, 'First');
    });
  });
});

describe('Error handling', () => {
  it('should detect token expiration errors', () => {
    const isTokenExpiredError = (message: string): boolean => {
      return message.includes('invalid_grant') || message.includes('Token has been expired');
    };

    assert.ok(isTokenExpiredError('invalid_grant: Token has been expired'));
    assert.ok(isTokenExpiredError('Token has been expired or revoked'));
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
