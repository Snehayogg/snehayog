FROM node:18-alpine

# Install FFmpeg and other necessary tools
RUN apk add --no-cache ffmpeg ffmpeg-dev

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies (production only)
RUN npm ci --only=production

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p logs temp uploads

# Expose port (DigitalOcean App Platform uses 8080 by default)
EXPOSE 8080

# Start the application
CMD ["npm", "start"]
