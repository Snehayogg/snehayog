provider "upstash" {
  email   = var.upstash_email
  api_key = var.upstash_api_key
}

resource "upstash_redis_database" "cache" {
  database_name = "Vayug"
  region        = "global"
  primary_region = "ap-south-1"
  tls           = true
  eviction      = true
}
