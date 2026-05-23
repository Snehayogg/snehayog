provider "fly" {
  token = var.fly_api_token
}

resource "fly_app" "vayug" {
  name = "vayug"
}

resource "fly_ip" "ipv4" {
  app  = fly_app.vayug.name
  type = "v4"
}

resource "fly_ip" "ipv6" {
  app  = fly_app.vayug.name
  type = "v6"
}

# Automatically provision required secrets on the deployed app container
resource "null_resource" "fly_secrets" {
  triggers = {
    fly_api_token = var.fly_api_token
    app_name      = fly_app.vayug.name
  }

  provisioner "local-exec" {
    command = "fly secrets set FLY_API_TOKEN='${var.fly_api_token}' FLY_APP_NAME='${fly_app.vayug.name}' --app ${fly_app.vayug.name}"
  }

  depends_on = [fly_app.vayug]
}
