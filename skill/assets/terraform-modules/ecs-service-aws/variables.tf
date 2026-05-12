variable "name" {
  description = "Service name (also used as task family + log group key)"
  type        = string
}

variable "env" {
  description = "Environment name: dev | staging | prod"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "container_image" {
  description = "Container image URI including tag/digest"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8000
}

variable "health_path" {
  description = "HTTP path for in-container health check"
  type        = string
  default     = "/health"
}

variable "cpu" {
  description = "Fargate task CPU units (256, 512, 1024, ...)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory in MB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of desired tasks"
  type        = number
  default     = 2
}

variable "env_vars" {
  description = "Plain environment variables (use secret_arns for sensitive values)"
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Map of env-var name -> Secrets Manager / SSM Parameter ARN"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "Private subnet IDs for the task ENIs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to the task ENIs"
  type        = list(string)
}

variable "target_group_arn" {
  description = "Optional ALB target group ARN to register tasks with"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log group retention"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
