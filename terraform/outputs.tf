output "webserver_public_ip" {
  description = "Public IP of the web server"
  value       = module.webserver.public_ip
}

output "dbserver_private_ip" {
  description = "Private IP of the DB server"
  value       = module.dbserver.private_ip
}
