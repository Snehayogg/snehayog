terraform {
  required_version = ">= 1.0.0"

  backend "s3" {
    bucket = "terraform-state-vayug"
    key    = "production/terraform.tfstate"
    
    # R2 endpoint format: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
    # I will use the account ID from your .env
    endpoints = {
      s3 = "https://c3c6f21fa187ec5534c488446cb3d0da.r2.cloudflarestorage.com"
    }

    region = "us-east-1" # Required for compatibility, though R2 is global
    
    # ACCESS_ID and SECRET_KEY will be passed via environment variables 
    # (AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY) during init
    
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style             = true
  }

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 1.15.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    upstash = {
      source  = "upstash/upstash"
      version = "~> 1.4.0"
    }
  }
}
