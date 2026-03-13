provider "yandex" {
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone
  service_account_key_file = var.sa_key_file
}

data "yandex_vpc_network" "dr" {
  name = var.network_name
}

data "yandex_vpc_subnet" "dr_a" {
  name = var.subnet_name
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

locals {
  otus_pubkey = trimspace(file(var.ssh_public_key_path))
}

# Статический public IP берём под управление через import
resource "yandex_vpc_address" "vpn_public" {
  name = "vpn-public-ip"
  external_ipv4_address {
    zone_id = var.zone
  }
}

# SG для VPN-ВМ: WG + SSH + минимальный egress
resource "yandex_vpc_security_group" "vpn_ingress" {
  name        = "sg-vpn-ingress"
  description = "VPN VM: WireGuard road-warrior + SSH from admin"
  network_id  = data.yandex_vpc_network.dr.id

  ingress {
    protocol       = "UDP"
    port           = 51820
    v4_cidr_blocks = ["0.0.0.0/0"]
    description    = "WireGuard road-warrior"
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.admin_ssh_cidrs
    description    = "SSH to VPN VM"
  }

  egress {
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["10.50.0.0/16", var.onprem_cidr, var.wg_clients_cidr]
    description    = "To VPC/onprem/WG ranges"
  }

  egress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
    description    = "HTTP"
  }

  egress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
    description    = "HTTPS"
  }

  egress {
    protocol       = "UDP"
    port           = 123
    v4_cidr_blocks = ["0.0.0.0/0"]
    description    = "NTP"
  }

  egress {
    protocol       = "UDP"
    port           = 53
    v4_cidr_blocks = ["10.50.0.0/16"]
    description    = "DNS inside VPC"
  }

  egress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["169.254.169.254/32"]
    description    = "YC metadata service"
  }
}

# Route table dr-rt: берём под управление через import и добавляем маршрут для WG-клиентов
resource "yandex_vpc_route_table" "dr_rt" {
  name       = "dr-rt"
  network_id = data.yandex_vpc_network.dr.id

  static_route {
    destination_prefix = var.onprem_cidr
    next_hop_address   = var.vpn_private_ip
  }

  static_route {
    destination_prefix = var.wg_clients_cidr
    next_hop_address   = var.vpn_private_ip
  }
}

resource "yandex_compute_instance" "vpn" {
  name        = "vpn-wg"
  hostname    = "vpn-wg"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 15
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = data.yandex_vpc_subnet.dr_a.id
    ip_address         = var.vpn_private_ip
    nat                = true
    nat_ip_address     = yandex_vpc_address.vpn_public.external_ipv4_address[0].address
    security_group_ids = [yandex_vpc_security_group.vpn_ingress.id]
  }

  # Вместо metadata.ssh-keys используем cloud-init user-data
  metadata = {
    user-data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      otus_pubkey = local.otus_pubkey
    })
  }
}
