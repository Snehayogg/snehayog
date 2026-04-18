#!/bin/bash

# Configuration
PROJECT_ID="67bea34b4adf7a7538fb4b62"
FLY_APP_NAME="vayug"
CLOUDFLARE_ACCOUNT_ID="c3c6f21fa187ec5534c488446cb3d0da"

echo "🚀 Starting Infrastructure Import..."

# 1. MongoDB Atlas Cluster
# Note: You need to specify project_id/cluster_name
echo "📦 Importing MongoDB Cluster: Cluster0"
terraform import mongodbatlas_cluster.production $PROJECT_ID/Cluster0

# 3. Cloudflare R2 Bucket
echo "📦 Importing Cloudflare R2: snehayog-videos"
terraform import cloudflare_r2_bucket.videos $CLOUDFLARE_ACCOUNT_ID/snehayog-videos

# 4. Upstash Redis
# Note: You need the database ID from Upstash dashboard/API
echo "📦 Importing Upstash Redis"
# terraform import upstash_redis_database.cache <DATABASE_ID>

echo "✅ Import sequence complete. Run 'terraform plan' to verify."
