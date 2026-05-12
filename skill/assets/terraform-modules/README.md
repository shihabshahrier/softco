# Terraform module stubs

Copy-and-adapt modules. Each is a starting point — production deployments
should review variables, IAM, tagging, monitoring, and lifecycle.

## Modules

| Module                | Purpose                                          |
| --------------------- | ------------------------------------------------ |
| `network-aws/`        | VPC + public/private subnets + NAT (single or HA)|
| `ecs-service-aws/`    | Fargate service + task roles + CW logs + secrets |
| `rds-postgres-aws/`   | RDS Postgres + backups + Secrets Manager DSN     |

## Usage pattern

```hcl
module "network" {
  source = "../../../skill/assets/terraform-modules/network-aws"
  name   = "softco-${var.env}"
  cidr   = "10.10.0.0/16"
  ha_nat = var.env == "prod"
  tags   = local.tags
}

module "db" {
  source                 = "../../../skill/assets/terraform-modules/rds-postgres-aws"
  name                   = "softco-${var.env}"
  env                    = var.env
  multi_az               = var.env == "prod"
  subnet_ids             = module.network.private_subnet_ids
  vpc_security_group_ids = [module.network.db_sg_id]
  tags                   = local.tags
}

module "api" {
  source             = "../../../skill/assets/terraform-modules/ecs-service-aws"
  name               = "api-${var.env}"
  env                = var.env
  cluster_arn        = aws_ecs_cluster.this.arn
  container_image    = "${var.ecr_repo}:${var.image_tag}"
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.network.app_sg_id]
  secret_arns        = { DATABASE_URL = module.db.connection_secret_arn }
  tags               = local.tags
}
```

## Notes

- These modules are AWS-only. GCP/Azure/DO equivalents follow the same shape
  — adapt or generate on demand.
- Run `tflint` + `tfsec` against the calling environment, not the modules in
  isolation.
- KMS, S3 backend, DynamoDB lock are environment-level, not module-level.
- Outputs are intentionally minimal — extend per project.
