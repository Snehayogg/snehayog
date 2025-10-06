# Use Flutter SDK image as base
FROM ghcr.io/cirruslabs/flutter:stable

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential \
    # Git for dependencies
    git \
    # Curl for health checks
    curl \
    # Unzip for extracting files
    unzip \
    # Clean up
    && rm -rf /var/lib/apt/lists/*

# Copy pubspec files first for better caching
COPY pubspec.yaml pubspec.lock ./

# Get Flutter dependencies
RUN flutter pub get

# Copy the monetization package
COPY ../snehayog_monetization /app/snehayog_monetization

# Copy the rest of the application
COPY . .

# Get dependencies again to include the monetization package
RUN flutter pub get

# Build the Flutter app for web
RUN flutter build web --release

# Use nginx to serve the built Flutter web app
FROM nginx:alpine

# Copy built Flutter app to nginx
COPY --from=0 /app/build/web /usr/share/nginx/html

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
