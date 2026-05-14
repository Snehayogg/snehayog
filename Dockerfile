FROM node:18-alpine

# Install FFmpeg and build dependencies for native modules
RUN apk add --no-cache ffmpeg ffmpeg-dev build-base g++ make python3 py3-pip

# Install edge-tts globally
RUN pip3 install edge-tts --break-system-packages

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
ENV PORT=8080
EXPOSE 8080

# Start the application
CMD ["npm", "start"]
