module "k8s-node" {
  source = "./k8s/k8s-node"
  hcloud_token = var.hcloud_token
  cloudflare_token = var.cloudflare_token
}