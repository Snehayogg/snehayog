# Terraform Import Script for PowerShell

$PROJECT_ID = "67bea34b4adf7a7538fb4b62"
$CLOUDFLARE_ACCOUNT_ID = "c3c6f21fa187ec5534c488446cb3d0da"

Write-Host "--- Starting Infrastructure Import ---" -ForegroundColor Cyan

# 1. MongoDB Atlas Cluster
Write-Host "[1/2] Importing MongoDB Cluster: Cluster0" -ForegroundColor Green
terraform import mongodbatlas_cluster.production "${PROJECT_ID}-Cluster0"

# 2. Cloudflare R2 Bucket
Write-Host "[2/2] Importing Cloudflare R2: snehayog-videos" -ForegroundColor Green
terraform import cloudflare_r2_bucket.videos "${CLOUDFLARE_ACCOUNT_ID}/snehayog-videos"

Write-Host "DONE: Import sequence complete. Now run: terraform plan" -ForegroundColor Cyan
