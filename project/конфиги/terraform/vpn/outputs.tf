output "vpn_public_ip" {
  value = yandex_vpc_address.vpn_public.external_ipv4_address[0].address
}

output "vpn_private_ip" {
  value = yandex_compute_instance.vpn.network_interface[0].ip_address
}
