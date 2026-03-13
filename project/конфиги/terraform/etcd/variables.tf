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

variable "sg_all_id" {
  type = string
}

variable "sg_admin_ssh_id" {
  type = string
}

variable "sg_etcd_id" {
  type = string
}

variable "etcd_nodes" {
  type = map(object({
    zone        = string
    subnet_name = string
    ip          = string
  }))
  default = {
    etcd1 = {
      zone        = "ru-central1-a"
      subnet_name = "dr-a"
      ip          = "10.50.10.11"
    }
    etcd2 = {
      zone        = "ru-central1-b"
      subnet_name = "dr-b"
      ip          = "10.50.20.11"
    }
    etcd3 = {
      zone        = "ru-central1-d"
      subnet_name = "dr-d"
      ip          = "10.50.30.11"
    }
  }
}
