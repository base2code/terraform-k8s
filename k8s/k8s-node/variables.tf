variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "server_config" {
  default = ({
    server_type   = "cax11"
    image         = "debian-12"
    k8s_instances = ["k8s-node-1", "k8s-node-2", "k8s-node-3"]
  })
}

variable "cloudflare_token" {
  type        = string
  sensitive   = true
}