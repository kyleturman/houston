/**
 * Gmail MCP Server Types
 *
 * Defines interfaces for multi-account Google connections and Gmail data structures.
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
 * When specified, limits operations to matching account(s).
 */
export interface AccountFilter {
  accountEmail?: string;   // Filter by account email (partial match, case-insensitive)
}

/**
 * Parsed Gmail message with account attribution.
 */
export interface GmailMessage {
  id: string;
  threadId: string;
  subject: string;
  from: string;
  to: string[];
  cc: string[];
  bcc: string[];
  date: string;
  snippet: string;
  body?: string;           // Full body when reading single email
  bodyHtml?: string;       // HTML body if available
  labels: string[];
  isUnread: boolean;
  hasAttachments: boolean;
  accountEmail: string;    // Which account this came from
}

/**
 * Gmail thread with messages.
 */
export interface GmailThread {
  id: string;
  subject: string;
  snippet: string;
  messages: GmailMessage[];
  messageCount: number;
  accountEmail: string;
}

/**
 * Gmail label/folder.
 */
export interface GmailLabel {
  id: string;
  name: string;
  type: 'system' | 'user';
  messageCount?: number;
  unreadCount?: number;
  accountEmail: string;
}

/**
 * Search parameters.
 */
export interface GmailSearchParams extends AccountFilter {
  query: string;           // Gmail search query (same syntax as Gmail search box)
  maxResults?: number;     // Default 20
  includeSpamTrash?: boolean; // Default false
}

/**
 * Read email parameters.
 */
export interface GmailReadParams extends AccountFilter {
  messageId: string;
  format?: 'full' | 'metadata' | 'minimal'; // Default 'full'
}

/**
 * Get thread parameters.
 */
export interface GmailGetThreadParams extends AccountFilter {
  threadId: string;
  format?: 'full' | 'metadata' | 'minimal'; // Default 'full'
}

/**
 * Send email parameters.
 */
export interface GmailSendParams extends AccountFilter {
  to: string[];
  subject: string;
  body: string;
  cc?: string[];
  bcc?: string[];
  isHtml?: boolean;        // Default false (plain text)
  replyToMessageId?: string; // For replies
  threadId?: string;       // To add to existing thread
}

/**
 * Create draft parameters.
 */
export interface GmailDraftParams extends AccountFilter {
  to: string[];
  subject: string;
  body: string;
  cc?: string[];
  bcc?: string[];
  isHtml?: boolean;
}

/**
 * List labels parameters.
 */
export interface GmailListLabelsParams extends AccountFilter {
  // No additional params needed
}
