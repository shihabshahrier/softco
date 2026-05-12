variable "name" {
  description = "DB identifier (becomes RDS instance ID and secret prefix)"
  type        = string
}

variable "env" {
  description = "Environment: dev | staging | prod (affects deletion protection, backup retention)"
  type        = string
}

variable "engine_version" {
  description = "Postgres engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.small"
}

variable "allocated_storage" {
  description = "Initial allocated storage (GB)"
  type        = number
  default     = 50
}

variable "max_allocated_storage" {
  description = "Storage autoscaling cap (GB). Set to 0 to disable."
  type        = number
  default     = 500
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username (rotated independently)"
  type        = string
  default     = "appadmin"
}

variable "multi_az" {
  description = "Multi-AZ deployment (true in prod)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "PITR / automated backup retention"
  type        = number
  default     = 14
}

variable "subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "Security groups allowed to reach the DB"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for storage encryption (null = AWS-managed)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
