FROM node:18-alpine

# Install FFmpeg and other necessary tools
RUN apk add --no-cache ffmpeg ffmpeg-dev

WORKDIR /app

# Copy package files from backend directory
COPY backend/package*.json ./

# Install dependencies (production only)
RUN npm ci --only=production

# Copy application code from backend directory
COPY backend/ .

# Create necessary directories
RUN mkdir -p logs temp uploads

# Expose port
EXPOSE 8080

# Start the application
CMD ["npm", "start"]
