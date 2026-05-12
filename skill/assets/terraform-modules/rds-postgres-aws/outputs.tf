output "endpoint" {
  description = "RDS endpoint host"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS endpoint port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.this.db_name
}

output "connection_secret_arn" {
  description = "Secrets Manager ARN holding the full DATABASE_URL"
  value       = aws_secretsmanager_secret.connection.arn
}

output "connection_secret_name" {
  description = "Secrets Manager secret name"
  value       = aws_secretsmanager_secret.connection.name
}
