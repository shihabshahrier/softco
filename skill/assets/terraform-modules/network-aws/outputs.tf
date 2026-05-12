output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets, one per AZ"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets, one per AZ"
  value       = aws_subnet.private[*].id
}

output "app_sg_id" {
  description = "Security group for application tier"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security group for database tier (accepts traffic from app SG only)"
  value       = aws_security_group.db.id
}
