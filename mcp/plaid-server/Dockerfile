FROM node:22-alpine

WORKDIR /app

# Install dependencies first (better layer caching)
COPY package*.json ./
RUN npm ci --only=production

# Copy source and build
COPY tsconfig.json ./
COPY src ./src
RUN npm install --save-dev typescript && \
    npm run build && \
    npm prune --production

# Run as non-root user
USER node

# Entry point
ENTRYPOINT ["node", "dist/index.js"]
