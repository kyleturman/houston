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
    email: string;
    access_token: string;
    refresh_token: string;
    expires_at: string;
}
/**
 * Common filter parameter for multi-account operations.
 * When specified, limits operations to matching account(s).
 */
export interface AccountFilter {
    accountEmail?: string;
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
    body?: string;
    bodyHtml?: string;
    labels: string[];
    isUnread: boolean;
    hasAttachments: boolean;
    accountEmail: string;
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
    query: string;
    maxResults?: number;
    includeSpamTrash?: boolean;
}
/**
 * Read email parameters.
 */
export interface GmailReadParams extends AccountFilter {
    messageId: string;
    format?: 'full' | 'metadata' | 'minimal';
}
/**
 * Get thread parameters.
 */
export interface GmailGetThreadParams extends AccountFilter {
    threadId: string;
    format?: 'full' | 'metadata' | 'minimal';
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
    isHtml?: boolean;
    replyToMessageId?: string;
    threadId?: string;
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
}
//# sourceMappingURL=types.d.ts.map