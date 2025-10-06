# Snehayog Docker Setup

This document provides instructions for running the Snehayog application using Docker containers.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 4GB RAM available for containers
- 10GB free disk space

## Quick Start

1. **Clone and navigate to the project:**
   ```bash
   cd snehayog
   ```

2. **Set up environment variables:**
   ```bash
   cp env.example .env
   # Edit .env with your actual values
   ```

3. **Start all services:**
   ```bash
   docker-compose up -d
   ```

4. **Check service status:**
   ```bash
   docker-compose ps
   ```

5. **View logs:**
   ```bash
   docker-compose logs -f
   ```

## Services

### Backend API (Port 5001)
- **Image:** Custom Node.js with FFmpeg
- **Health Check:** `http://localhost:5001/health`
- **Features:** Video processing, user management, payments

### Frontend Web (Port 80)
- **Image:** Flutter web app served by Nginx
- **Health Check:** `http://localhost/health`
- **Features:** User interface, video streaming

### MongoDB (Port 27017)
- **Image:** MongoDB 7.0
- **Features:** User data, videos, comments, payments

### Redis (Port 6379)
- **Image:** Redis 7.2 Alpine
- **Features:** Caching, session storage

## Environment Variables

Copy `env.example` to `.env` and configure:

### Required Variables
- `JWT_SECRET`: Secret key for JWT tokens
- `RAZORPAY_KEY_ID` & `RAZORPAY_KEY_SECRET`: Payment gateway credentials
- `GOOGLE_CLIENT_ID` & `GOOGLE_CLIENT_SECRET`: Google OAuth credentials
- `CLOUDINARY_*`: Image/video storage credentials
- `CLOUDFLARE_R2_*`: Video storage credentials

### Optional Variables
- `MONGO_ROOT_USERNAME` & `MONGO_ROOT_PASSWORD`: Database credentials
- `NODE_ENV`: Environment (development/production)
- Feature flags for enabling/disabling features

## Development Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Rebuild and start
docker-compose up --build -d

# View logs
docker-compose logs -f [service_name]

# Execute commands in containers
docker-compose exec backend npm run dev
docker-compose exec frontend flutter pub get

# Clean up everything
docker-compose down -v --remove-orphans
```

## Production Deployment

1. **Set production environment:**
   ```bash
   export NODE_ENV=production
   ```

2. **Use production compose file:**
   ```bash
   docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
   ```

3. **Set up reverse proxy (Nginx/Traefik) for SSL termination**

## Troubleshooting

### Common Issues

1. **Port conflicts:**
   ```bash
   # Check what's using the ports
   netstat -tulpn | grep :5001
   netstat -tulpn | grep :80
   ```

2. **Permission issues:**
   ```bash
   # Fix upload directory permissions
   sudo chown -R 1001:1001 uploads/
   ```

3. **Memory issues:**
   ```bash
   # Check container resource usage
   docker stats
   ```

4. **Database connection issues:**
   ```bash
   # Check MongoDB logs
   docker-compose logs mongodb
   ```

### Health Checks

- Backend: `curl http://localhost:5001/health`
- Frontend: `curl http://localhost/health`
- MongoDB: `docker-compose exec mongodb mongosh --eval "db.adminCommand('ping')"`

## Security Considerations

1. **Change default passwords** in production
2. **Use secrets management** for sensitive data
3. **Enable SSL/TLS** termination
4. **Configure firewall** rules
5. **Regular security updates** of base images

## Monitoring

- **Container logs:** `docker-compose logs -f`
- **Resource usage:** `docker stats`
- **Health status:** Check health endpoints
- **Database status:** MongoDB admin commands

## Backup & Recovery

```bash
# Backup MongoDB
docker-compose exec mongodb mongodump --out /backup

# Backup uploads
docker cp snehayog-backend:/app/uploads ./backup-uploads

# Restore MongoDB
docker-compose exec mongodb mongorestore /backup
```

## Scaling

For production scaling:

1. **Use external MongoDB** (MongoDB Atlas)
2. **Use external Redis** (Redis Cloud)
3. **Use load balancer** for multiple backend instances
4. **Use CDN** for static assets
5. **Use container orchestration** (Kubernetes)

## Support

For issues related to Docker setup, check:
1. Container logs: `docker-compose logs`
2. Service health: Health check endpoints
3. Resource usage: `docker stats`
4. Network connectivity: `docker network ls`
