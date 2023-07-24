resource "hcloud_ssh_key" "root-ssh-key" {
  name       = "ssh-key"
  public_key = file("./.ssh/id_rsa.pub")
}

locals {
  k8s_ip_addresses = join(",", [for s in hcloud_server.k8s : s.ipv4_address])
}

resource "tls_private_key" "ssh-keys" {
  for_each  = toset(var.server_config.k8s_instances)
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "null_resource" "ssh_keys_setup" {
  for_each = toset(var.server_config.k8s_instances)

  provisioner "local-exec" {
    command = <<EOF
        if [ -d .ssh ]; then rm .ssh-${each.key}; fi
        mkdir .ssh-${each.key}
        echo "${tls_private_key.ssh-keys[each.key].private_key_openssh}" > .ssh-${each.key}/id_rsa
        echo "${tls_private_key.ssh-keys[each.key].public_key_openssh}" > .ssh-${each.key}/id_rsa.pub
        chmod 400 .ssh-${each.key}/id_rsa
        chmod 400 .ssh-${each.key}/id_rsa.pub
      EOF
  }

  triggers = {
    private_key_openssh = tls_private_key.ssh-keys[each.key].private_key_openssh
    public_key_openssh  = tls_private_key.ssh-keys[each.key].public_key_openssh
    always_run          = "${timestamp()}"
  }
}

resource "null_resource" "authorized_keys_setup" {
  for_each = toset(var.server_config.k8s_instances)

  provisioner "local-exec" {
    command = <<EOF
        > ./authorized_keys && for dir in .ssh-*/; do [ -f "$dir/id_rsa.pub" ] && cat "$dir/id_rsa.pub" >> ./authorized_keys; done
      EOF
  }

  triggers = {
    private_key_openssh = tls_private_key.ssh-keys[each.key].private_key_openssh
    public_key_openssh  = tls_private_key.ssh-keys[each.key].public_key_openssh
    always_run          = "${timestamp()}"
  }
}

resource "hcloud_server" "k8s" {
  for_each    = toset(var.server_config.k8s_instances)
  name        = each.key
  server_type = var.server_config.server_type
  image       = var.server_config.image
  ssh_keys    = [hcloud_ssh_key.root-ssh-key.name]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("./.ssh/id_rsa")
    host        = self.ipv4_address
  }

  provisioner "file" {
    source      = "./k8s/k8s-node/bin/01_install.sh"
    destination = "/tmp/01_install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      <<EOF
      useradd -m rke
      mkdir -p /home/rke/.ssh/
    EOF
    ]
  }

  provisioner "file" {
    source      = ".ssh-${each.key}/"
    destination = "/home/rke/.ssh/"
  }

  provisioner "file" {
    source      = "authorized_keys"
    destination = "/home/rke/.ssh/authorized_keys"
  }

  provisioner "remote-exec" {
    inline = [
      <<EOF
      chmod +x /tmp/01_install.sh
      bash /tmp/01_install.sh
    EOF
    ]
  }

  depends_on = [
    tls_private_key.ssh-keys,
    null_resource.ssh_keys_setup,
    null_resource.authorized_keys_setup,
  ]
}

resource "null_resource" "reboot" {
  for_each = hcloud_server.k8s

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("./.ssh/id_rsa")
    host        = each.value.ipv4_address
  }

  provisioner "remote-exec" {
    script = "./k8s/k8s-node/bin/99_reboot.sh"
  }
}

resource "hcloud_load_balancer" "load_balancer" {
  name               = "my-load-balancer"
  load_balancer_type = "lb11"
  location           = "nbg1"
}

resource "hcloud_load_balancer_target" "load_balancer_target" {
  for_each         = hcloud_server.k8s
  type             = "server"
  load_balancer_id = hcloud_load_balancer.load_balancer.id
  server_id        = each.value.id
}

resource "hcloud_load_balancer_service" "load_balancer_service_8443" {
  load_balancer_id = hcloud_load_balancer.load_balancer.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 8443
}

resource "hcloud_load_balancer_service" "load_balancer_service_443" {
  load_balancer_id = hcloud_load_balancer.load_balancer.id
  protocol         = "tcp"
  listen_port      = 8443
  destination_port = 443
}

resource "hcloud_load_balancer_service" "load_balancer_service_80" {
  load_balancer_id = hcloud_load_balancer.load_balancer.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80
}


resource "null_resource" "k8s-init" {
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("./.ssh/id_rsa")
    host        = hcloud_server.k8s[keys(hcloud_server.k8s)[0]].ipv4_address
  }

  provisioner "local-exec" {
    # Wait 80 sec to make sure all nodes are up and running (see reboot resource)
    command = "sleep 80; chmod +x ./k8s/k8s-node/local-bin/01_generate_clusteryml.sh && ./k8s/k8s-node/local-bin/01_generate_clusteryml.sh ${local.k8s_ip_addresses}"
  }

  provisioner "file" {
    source      = "./cluster.yml"
    destination = "/root/cluster.yml"
  }

  provisioner "file" {
    source      = "./k8s/k8s-node/bin/02_create_cluster.sh"
    destination = "/tmp/02_create_cluster.sh"
  }

  provisioner "file" {
    source      = ".ssh-${hcloud_server.k8s[keys(hcloud_server.k8s)[0]].name}/"
    destination = "/root/.ssh/"
  }

  provisioner "remote-exec" {
    inline = [
      <<EOF
      chmod +x /tmp/02_create_cluster.sh
      bash /tmp/02_create_cluster.sh k8s.base2code.dev
    EOF
    ]
  }

  depends_on = [
    hcloud_server.k8s,
    tls_private_key.ssh-keys,
    null_resource.ssh_keys_setup,
    null_resource.authorized_keys_setup,
    null_resource.reboot,
    cloudflare_record.k8s-base2code-dev
  ]
}

resource "null_resource" "k8s-update" {
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("./.ssh/id_rsa")
    host        = hcloud_server.k8s[keys(hcloud_server.k8s)[0]].ipv4_address
  }

  provisioner "local-exec" {
    command = "chmod +x ./k8s/k8s-node/local-bin/01_generate_clusteryml.sh && ./k8s/k8s-node/local-bin/01_generate_clusteryml.sh ${local.k8s_ip_addresses}"
  }

  provisioner "file" {
    source      = "./cluster.yml"
    destination = "/root/cluster.yml"
  }

  provisioner "file" {
    source      = "./k8s/k8s-node/bin/03_update_cluster.sh"
    destination = "/tmp/02_update_cluster.sh"
  }

  provisioner "remote-exec" {
    inline = [
      <<EOF
      chmod +x /tmp/02_update_cluster.sh
      bash /tmp/02_update_cluster.sh
    EOF
    ]
  }

  depends_on = [
    hcloud_server.k8s,
    tls_private_key.ssh-keys,
    null_resource.ssh_keys_setup,
    null_resource.authorized_keys_setup,
    null_resource.reboot,
    null_resource.k8s-init
  ]

  triggers = {
    timestamp = "${timestamp()}"
  }
}

resource "null_resource" "copy_files" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "ssh-keygen -R ${hcloud_server.k8s[keys(hcloud_server.k8s)[0]].ipv4_address}"
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ./.ssh/id_rsa root@${hcloud_server.k8s[keys(hcloud_server.k8s)[0]].ipv4_address}:/root/cluster.yml ."
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ./.ssh/id_rsa root@${hcloud_server.k8s[keys(hcloud_server.k8s)[0]].ipv4_address}:/root/kube_config_cluster.yml ."
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ./.ssh/id_rsa root@${hcloud_server.k8s[keys(hcloud_server.k8s)[0]].ipv4_address}:/root/cluster.rkestate ."
  }

  depends_on = [
    null_resource.k8s-init
  ]
}
