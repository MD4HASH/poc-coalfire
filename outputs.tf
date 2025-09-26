output "alb_dns_name" {
  value = module.alb.lb_dns_name
}

output "mgmt_server_ip" {
  value = module.mgmt_server.public_ip[0]
}
