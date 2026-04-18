provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_r2_bucket" "videos" {
  account_id = var.cloudflare_account_id
  name       = "snehayog-videos"
  location   = "APAC"
}

# Add state bucket
resource "cloudflare_r2_bucket" "terraform_state" {
  account_id = var.cloudflare_account_id
  name       = "terraform-state-vayug"
  location   = "APAC"
}
