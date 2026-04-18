provider "mongodbatlas" {
  public_key  = var.mongodb_atlas_public_key
  private_key = var.mongodb_atlas_private_key
}

resource "mongodbatlas_cluster" "production" {
  project_id = var.mongodb_atlas_project_id
  name       = "Cluster0" # Based on your .env URL

  cluster_type = "REPLICASET"
  replication_specs {
    num_shards = 1
    regions_config {
      region_name     = "AP_SOUTH_1" # Mumbai (bom in fly, AP_SOUTH_1 in AWS/Atlas)
      priority        = 7
      electable_nodes = 3
    }
  }

  cloud_backup                 = false
  auto_scaling_compute_enabled = false
  provider_name               = "TENANT"
  backing_provider_name       = "AWS"
  provider_instance_size_name = "M0"

  lifecycle {
    ignore_changes = [
      replication_specs,
    ]
  }
}

# Database User
resource "mongodbatlas_database_user" "admin" {
  username           = "factshorts1"
  password           = "Snehayog@123"
  project_id         = var.mongodb_atlas_project_id
  auth_database_name = "admin"

  roles {
    role_name     = "atlasAdmin"
    database_name = "admin"
  }
}
