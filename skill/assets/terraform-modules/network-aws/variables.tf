variable "name" {
  description = "Project + environment name prefix (e.g. softco-dev)"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.10.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (and matching public/private subnets)"
  type        = number
  default     = 3
}

variable "ha_nat" {
  description = "If true, one NAT gateway per AZ (prod). If false, one shared NAT (dev/staging)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
