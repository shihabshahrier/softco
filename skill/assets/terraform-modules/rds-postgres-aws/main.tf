# RDS Postgres with: encrypted storage, PITR, Multi-AZ option, parameter group
# tuned for app workloads, secret stored in Secrets Manager for app injection.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.60" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db-subnets"
  description = "DB subnet group for ${var.name}"
  subnet_ids  = var.subnet_ids
  tags        = var.tags
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-pg16"
  family      = "postgres16"
  description = "App-tuned Postgres parameters"

  parameter { name = "log_min_duration_statement", value = "500" }
  parameter { name = "shared_preload_libraries",   value = "pg_stat_statements", apply_method = "pending-reboot" }
}

resource "aws_db_instance" "this" {
  identifier              = var.name
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  max_allocated_storage   = var.max_allocated_storage
  storage_type            = "gp3"
  storage_encrypted       = true
  kms_key_id              = var.kms_key_arn
  db_name                 = var.db_name
  username                = var.master_username
  password                = random_password.master.result
  port                    = 5432
  publicly_accessible     = false
  multi_az                = var.multi_az
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = var.vpc_security_group_ids
  parameter_group_name    = aws_db_parameter_group.this.name
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot   = true
  deletion_protection     = var.env == "prod"
  skip_final_snapshot     = var.env != "prod"
  final_snapshot_identifier = var.env == "prod" ? "${var.name}-final-${formatdate("YYYYMMDDhhmm", timestamp())}" : null
  performance_insights_enabled = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately      = var.env != "prod"
  tags = var.tags

  lifecycle { ignore_changes = [final_snapshot_identifier] }
}

resource "aws_secretsmanager_secret" "connection" {
  name                    = "${var.name}/connection"
  description             = "DATABASE_URL for ${var.name}"
  recovery_window_in_days = var.env == "prod" ? 7 : 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "connection" {
  secret_id     = aws_secretsmanager_secret.connection.id
  secret_string = "postgresql+asyncpg://${var.master_username}:${urlencode(random_password.master.result)}@${aws_db_instance.this.address}:5432/${var.db_name}"
}
