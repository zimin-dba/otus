variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "ru-central1-a"
}

# путь до key.json
variable "sa_key_file" {
  type = string
}

variable "network_name" {
  type    = string
  default = "dr-net"
}

variable "subnet_name" {
  type    = string
  default = "dr-a"
}

variable "vpn_private_ip" {
  type    = string
  default = "10.50.10.200"
}

# ваш pubkey
variable "ssh_public_key_path" {
  type = string
}

# CIDR(ы), с которых будет SSH на VPN-ВМ
variable "admin_ssh_cidrs" {
  type = list(string)
}

# Для маршрутов
variable "wg_clients_cidr" {
  type    = string
  default = "10.60.0.0/24"
}

variable "onprem_cidr" {
  type    = string
  default = "192.168.1.0/24"
}
