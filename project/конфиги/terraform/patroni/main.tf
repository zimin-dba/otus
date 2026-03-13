provider "yandex" {
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  service_account_key_file = var.service_account_key_file
}

data "yandex_compute_image" "ubuntu" {
  family = var.image_family
}

data "yandex_vpc_subnet" "subnets" {
  for_each = toset([
    var.subnet_a_name,
    var.subnet_b_name,
    var.subnet_d_name
  ])
  name = each.value
}

locals {
  ssh_public_key = trimspace(file(var.ssh_public_key_path))
}

resource "yandex_compute_instance" "patroni" {
  for_each = var.patroni_nodes

  name        = each.key
  hostname    = each.key
  zone        = each.value.zone
  platform_id = var.platform_id

  resources {
    cores         = var.cores
    memory        = var.memory
    core_fraction = var.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.disk_size_gb
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id  = data.yandex_vpc_subnet.subnets[each.value.subnet_name].id
    ip_address = each.value.ip

    # По аналогии с etcd: даём публичный IP (удобно для обновлений/доступа),
    # ansible_host в inventory всё равно будет private IP.
    nat = true

    # sg_patroni_id можно будет добавить позже без правок tfvars (он optional).
    security_group_ids = compact([
      var.sg_all_id,
      var.sg_admin_ssh_id,
      var.sg_patroni_id
    ])
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      hostname       = each.key
      ssh_user       = var.ssh_user
      ssh_public_key = local.ssh_public_key
    })
  }

  scheduling_policy {
    preemptible = false
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../../../generated/inventory/patroni.yml"
  content  = yamlencode({
    all = {
      children = {
        patroni = {
          hosts = {
            for name, vm in yandex_compute_instance.patroni :
            name => {
              ansible_host  = one(vm.network_interface[*].ip_address)
              private_ip    = one(vm.network_interface[*].ip_address)
              public_ip     = one(vm.network_interface[*].nat_ip_address)
              patroni_name  = name
              patroni_rest  = "${one(vm.network_interface[*].ip_address)}:8008"
              postgres_addr = "${one(vm.network_interface[*].ip_address)}:5432"
            }
          }
        }
      }
    }
  })
}
