FROM node:18-slim

# Install system dependencies
# We use debian-slim for better compatibility with native C++ modules (onnxruntime, sharp)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    python3 \
    python3-pip \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install edge-tts for AI voice generation
RUN pip3 install edge-tts --break-system-packages

WORKDIR /app

# Copy package files
COPY backend/package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY backend/ .

# Create persistent/temp directories
RUN mkdir -p logs temp uploads

# Fly.io expects port 8080 by default
ENV PORT=8080
ENV NODE_ENV=production
EXPOSE 8080

# Start command
CMD ["npm", "start"]
