variable "mongodb_atlas_public_key" {
  description = "MongoDB Atlas Public Programmatic API Key"
  type        = string
}

variable "mongodb_atlas_private_key" {
  description = "MongoDB Atlas Private Programmatic API Key"
  type        = string
  sensitive   = true
}

variable "mongodb_atlas_project_id" {
  description = "MongoDB Atlas Project ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "upstash_email" {
  description = "Upstash account email"
  type        = string
}

variable "upstash_api_key" {
  description = "Upstash API Key"
  type        = string
  sensitive   = true
}
