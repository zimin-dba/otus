variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "zone_a" {
  type    = string
  default = "ru-central1-a"
}

variable "zone_b" {
  type    = string
  default = "ru-central1-b"
}

variable "zone_d" {
  type    = string
  default = "ru-central1-d"
}

variable "service_account_key_file" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "otus-sb"
}

variable "ssh_public_key_path" {
  type = string
}

variable "image_family" {
  type    = string
  default = "ubuntu-2404-lts"
}

variable "platform_id" {
  type    = string
  default = "standard-v3"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2
}

variable "core_fraction" {
  type    = number
  default = 20
}

variable "disk_size_gb" {
  type    = number
  default = 15
}

variable "network_name" {
  type    = string
  default = "dr-net"
}

variable "subnet_a_name" {
  type    = string
  default = "dr-a"
}

variable "subnet_b_name" {
  type    = string
  default = "dr-b"
}

variable "subnet_d_name" {
  type    = string
  default = "dr-d"
}

# Эти переменные уже есть в tfvars для etcd — оставляю 1-в-1.
variable "sg_all_id" {
  type = string
}

variable "sg_admin_ssh_id" {
  type = string
}

# Оставляем ради совместимости с terraform.tfvars из etcd
variable "sg_etcd_id" {
  type = string
}

# Опционально: SG именно для patroni/postgres (8008/5432 и т.п.)
# Можно добавить позже, не меняя tfvars (если переменной там нет).
variable "sg_patroni_id" {
  type    = string
  default = null
}

variable "patroni_nodes" {
  type = map(object({
    zone        = string
    subnet_name = string
    ip          = string
  }))
  default = {
    dr-pg1 = {
      zone        = "ru-central1-a"
      subnet_name = "dr-a"
      ip          = "10.50.10.21"
    }
    dr-pg2 = {
      zone        = "ru-central1-b"
      subnet_name = "dr-b"
      ip          = "10.50.20.21"
    }
  }
}
