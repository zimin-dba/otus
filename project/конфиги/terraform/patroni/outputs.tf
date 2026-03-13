output "patroni_private_ips" {
  value = {
    for name, vm in yandex_compute_instance.patroni :
    name => one(vm.network_interface[*].ip_address)
  }
}

output "patroni_public_ips" {
  value = {
    for name, vm in yandex_compute_instance.patroni :
    name => one(vm.network_interface[*].nat_ip_address)
  }
}

output "generated_inventory_file" {
  value = local_file.ansible_inventory.filename
}
