resource "cloudflare_record" "k8s-base2code-dev" {
  zone_id = "a612b8224bf198c00ca048ec42a15ecf"
  name    = "k8s"
  value   = hcloud_load_balancer.load_balancer.ipv4
  type    = "A"
  ttl = 1
}

resource "cloudflare_record" "wildcard-k8s-base2code-dev" {
  zone_id = "a612b8224bf198c00ca048ec42a15ecf"
  name    = "*.k8s"
  value   = hcloud_load_balancer.load_balancer.ipv4
  type    = "A"
    ttl = 1
}