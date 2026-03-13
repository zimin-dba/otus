output "etcd_private_ips" {
  value = {
    for name, vm in yandex_compute_instance.etcd :
    name => one(vm.network_interface[*].ip_address)
  }
}

output "etcd_public_ips" {
  value = {
    for name, vm in yandex_compute_instance.etcd :
    name => one(vm.network_interface[*].nat_ip_address)
  }
}

output "generated_inventory_file" {
  value = local_file.ansible_inventory.filename
}
