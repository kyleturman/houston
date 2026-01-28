/**
 * Gmail API Client
 *
 * Wraps Google Gmail API with typed methods for common operations.
 * Handles message parsing, encoding, and error handling.
 */
import { GoogleConnection, GmailMessage, GmailThread, GmailLabel } from './types.js';
/**
 * Gmail client for a single Google account.
 */
export declare class GmailClient {
    private gmail;
    private accountEmail;
    constructor(connection: GoogleConnection);
    /**
     * Search for messages using Gmail query syntax.
     */
    search(query: string, maxResults?: number, includeSpamTrash?: boolean): Promise<GmailMessage[]>;
    /**
     * Get a single message by ID.
     */
    getMessage(messageId: string, format?: 'full' | 'metadata' | 'minimal'): Promise<GmailMessage | null>;
    /**
     * Get a thread with all its messages.
     */
    getThread(threadId: string, format?: 'full' | 'metadata' | 'minimal'): Promise<GmailThread | null>;
    /**
     * List all labels.
     */
    listLabels(): Promise<GmailLabel[]>;
    /**
     * Send an email.
     */
    sendEmail(params: {
        to: string[];
        subject: string;
        body: string;
        cc?: string[];
        bcc?: string[];
        isHtml?: boolean;
        replyToMessageId?: string;
        threadId?: string;
    }): Promise<GmailMessage>;
    /**
     * Create a draft email.
     */
    createDraft(params: {
        to: string[];
        subject: string;
        body: string;
        cc?: string[];
        bcc?: string[];
        isHtml?: boolean;
    }): Promise<{
        draftId: string;
        message: GmailMessage;
    }>;
    /**
     * Parse a Gmail API message into our GmailMessage type.
     */
    private parseMessage;
    /**
     * Extract plain text and HTML body from message payload.
     */
    private extractBody;
    /**
     * Check if message has attachments.
     */
    private hasAttachments;
    /**
     * Create raw email in RFC 2822 format for sending.
     */
    private createRawEmail;
    /**
     * Decode base64url encoded string.
     */
    private decodeBase64Url;
    /**
     * Encode string to base64url.
     */
    private encodeBase64Url;
}
//# sourceMappingURL=gmail-client.d.ts.map