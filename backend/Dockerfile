# Use Node.js 18 LTS as base image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Install system dependencies required for the application
RUN apk add --no-cache \
    # FFmpeg for video processing
    ffmpeg \
    # Python and build tools for native dependencies
    python3 \
    make \
    g++ \
    # Image processing libraries
    vips-dev \
    # Git for potential git dependencies
    git \
    # Curl for health checks
    curl \
    # Timezone data
    tzdata

# Set timezone
ENV TZ=Asia/Kolkata

# Copy package files first for better caching
COPY package*.json ./

# Install Node.js dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p uploads/videos uploads/thumbnails uploads/hls uploads/ads uploads/temp

# Set proper permissions
RUN chmod -R 755 uploads/

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Change ownership of the app directory
RUN chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 5001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5001/health || exit 1

# Start the application
CMD ["npm", "start"]
