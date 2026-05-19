output "alb_dns_name" {
  description = "DNS del Application Load Balancer (punto de entrada)"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN del ALB"
  value       = aws_lb.main.arn
}

output "vpc_id" {
  description = "ID del VPC creado"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs de las subnets publicas"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas (RDS)"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "rds_primary_endpoint" {
  description = "Endpoint de la instancia RDS primaria"
  value       = aws_db_instance.primary.address
  sensitive   = true
}

output "rds_replica_endpoint" {
  description = "Endpoint de la replica de lectura RDS"
  value       = aws_db_instance.replica.address
  sensitive   = true
}

output "service_url" {
  description = "URL del servicio desplegado"
  value       = "http://${aws_lb.main.dns_name}"
}

output "health_check_url" {
  description = "URL del endpoint de health check"
  value       = "http://${aws_lb.main.dns_name}/health"
}
