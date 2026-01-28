/**
 * Gmail API Client
 *
 * Wraps Google Gmail API with typed methods for common operations.
 * Handles message parsing, encoding, and error handling.
 */
import { google } from 'googleapis';
/**
 * Gmail client for a single Google account.
 */
export class GmailClient {
    gmail;
    accountEmail;
    constructor(connection) {
        const auth = new google.auth.OAuth2();
        auth.setCredentials({
            access_token: connection.access_token,
            refresh_token: connection.refresh_token,
        });
        this.gmail = google.gmail({ version: 'v1', auth });
        this.accountEmail = connection.email;
    }
    /**
     * Search for messages using Gmail query syntax.
     */
    async search(query, maxResults = 20, includeSpamTrash = false) {
        const response = await this.gmail.users.messages.list({
            userId: 'me',
            q: query,
            maxResults,
            includeSpamTrash,
        });
        const messages = response.data.messages || [];
        const results = [];
        // Fetch full message details in parallel (batched)
        const batchSize = 10;
        for (let i = 0; i < messages.length; i += batchSize) {
            const batch = messages.slice(i, i + batchSize);
            const details = await Promise.all(batch.map(msg => this.getMessage(msg.id, 'metadata')));
            results.push(...details.filter((d) => d !== null));
        }
        return results;
    }
    /**
     * Get a single message by ID.
     */
    async getMessage(messageId, format = 'full') {
        try {
            const response = await this.gmail.users.messages.get({
                userId: 'me',
                id: messageId,
                format,
            });
            return this.parseMessage(response.data);
        }
        catch (error) {
            if (error.code === 404) {
                return null;
            }
            throw error;
        }
    }
    /**
     * Get a thread with all its messages.
     */
    async getThread(threadId, format = 'full') {
        try {
            const response = await this.gmail.users.threads.get({
                userId: 'me',
                id: threadId,
                format,
            });
            const messages = (response.data.messages || []).map(msg => this.parseMessage(msg));
            const firstMessage = messages[0];
            return {
                id: response.data.id,
                subject: firstMessage?.subject || '',
                snippet: response.data.snippet || '',
                messages,
                messageCount: messages.length,
                accountEmail: this.accountEmail,
            };
        }
        catch (error) {
            if (error.code === 404) {
                return null;
            }
            throw error;
        }
    }
    /**
     * List all labels.
     */
    async listLabels() {
        const response = await this.gmail.users.labels.list({
            userId: 'me',
        });
        return (response.data.labels || []).map(label => ({
            id: label.id,
            name: label.name,
            type: label.type === 'system' ? 'system' : 'user',
            messageCount: label.messagesTotal ?? undefined,
            unreadCount: label.messagesUnread ?? undefined,
            accountEmail: this.accountEmail,
        }));
    }
    /**
     * Send an email.
     */
    async sendEmail(params) {
        const raw = this.createRawEmail(params);
        const response = await this.gmail.users.messages.send({
            userId: 'me',
            requestBody: {
                raw,
                threadId: params.threadId,
            },
        });
        // Fetch the sent message to return full details
        const sentMessage = await this.getMessage(response.data.id, 'full');
        if (!sentMessage) {
            throw new Error('Failed to retrieve sent message');
        }
        return sentMessage;
    }
    /**
     * Create a draft email.
     */
    async createDraft(params) {
        const raw = this.createRawEmail(params);
        const response = await this.gmail.users.drafts.create({
            userId: 'me',
            requestBody: {
                message: { raw },
            },
        });
        const message = await this.getMessage(response.data.message.id, 'full');
        if (!message) {
            throw new Error('Failed to retrieve draft message');
        }
        return {
            draftId: response.data.id,
            message,
        };
    }
    /**
     * Parse a Gmail API message into our GmailMessage type.
     */
    parseMessage(msg) {
        const headers = msg.payload?.headers || [];
        const getHeader = (name) => {
            const header = headers.find(h => h.name?.toLowerCase() === name.toLowerCase());
            return header?.value || '';
        };
        const parseAddressList = (value) => {
            if (!value)
                return [];
            // Simple parsing - splits on comma but respects quoted strings
            return value.split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/).map(s => s.trim()).filter(Boolean);
        };
        const labels = msg.labelIds || [];
        const isUnread = labels.includes('UNREAD');
        // Extract body
        let body = '';
        let bodyHtml = '';
        if (msg.payload) {
            const extracted = this.extractBody(msg.payload);
            body = extracted.plain;
            bodyHtml = extracted.html;
        }
        // Check for attachments
        const hasAttachments = this.hasAttachments(msg.payload);
        return {
            id: msg.id,
            threadId: msg.threadId,
            subject: getHeader('Subject'),
            from: getHeader('From'),
            to: parseAddressList(getHeader('To')),
            cc: parseAddressList(getHeader('Cc')),
            bcc: parseAddressList(getHeader('Bcc')),
            date: getHeader('Date'),
            snippet: msg.snippet || '',
            body,
            bodyHtml,
            labels,
            isUnread,
            hasAttachments,
            accountEmail: this.accountEmail,
        };
    }
    /**
     * Extract plain text and HTML body from message payload.
     */
    extractBody(payload) {
        let plain = '';
        let html = '';
        const extractFromPart = (part) => {
            if (part.mimeType === 'text/plain' && part.body?.data) {
                plain = this.decodeBase64Url(part.body.data);
            }
            else if (part.mimeType === 'text/html' && part.body?.data) {
                html = this.decodeBase64Url(part.body.data);
            }
            if (part.parts) {
                for (const subpart of part.parts) {
                    extractFromPart(subpart);
                }
            }
        };
        extractFromPart(payload);
        // If body is directly on payload (simple messages)
        if (!plain && !html && payload.body?.data) {
            const decoded = this.decodeBase64Url(payload.body.data);
            if (payload.mimeType === 'text/html') {
                html = decoded;
            }
            else {
                plain = decoded;
            }
        }
        return { plain, html };
    }
    /**
     * Check if message has attachments.
     */
    hasAttachments(payload) {
        if (!payload)
            return false;
        const checkPart = (part) => {
            if (part.filename && part.filename.length > 0) {
                return true;
            }
            if (part.parts) {
                return part.parts.some(checkPart);
            }
            return false;
        };
        return checkPart(payload);
    }
    /**
     * Create raw email in RFC 2822 format for sending.
     */
    createRawEmail(params) {
        const boundary = `boundary_${Date.now()}`;
        const contentType = params.isHtml ? 'text/html' : 'text/plain';
        let email = '';
        email += `To: ${params.to.join(', ')}\r\n`;
        if (params.cc && params.cc.length > 0) {
            email += `Cc: ${params.cc.join(', ')}\r\n`;
        }
        if (params.bcc && params.bcc.length > 0) {
            email += `Bcc: ${params.bcc.join(', ')}\r\n`;
        }
        email += `Subject: ${params.subject}\r\n`;
        if (params.replyToMessageId) {
            email += `In-Reply-To: ${params.replyToMessageId}\r\n`;
            email += `References: ${params.replyToMessageId}\r\n`;
        }
        email += `MIME-Version: 1.0\r\n`;
        email += `Content-Type: ${contentType}; charset=utf-8\r\n`;
        email += `\r\n`;
        email += params.body;
        return this.encodeBase64Url(email);
    }
    /**
     * Decode base64url encoded string.
     */
    decodeBase64Url(data) {
        // Replace URL-safe characters and add padding
        const base64 = data.replace(/-/g, '+').replace(/_/g, '/');
        const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
        return Buffer.from(padded, 'base64').toString('utf-8');
    }
    /**
     * Encode string to base64url.
     */
    encodeBase64Url(data) {
        return Buffer.from(data, 'utf-8')
            .toString('base64')
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/, '');
    }
}
//# sourceMappingURL=gmail-client.js.map