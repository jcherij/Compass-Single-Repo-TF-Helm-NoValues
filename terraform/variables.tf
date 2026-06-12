variable "aws_region" {
  description = "AWS region for Compass deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID for this deployment — differs between production and dev"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (production or dev) — used in resource naming"
  type        = string
}

variable "resource_prefix" {
  description = "Globally-unique prefix for S3 bucket names (typically the AWS account ID or an account alias)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which Compass AWS resources are deployed"
  type        = string
}

variable "db_subnet_group_name" {
  description = "DB subnet group name for the Aurora cluster"
  type        = string
}

variable "elasticache_subnet_group_name" {
  description = "Subnet group name for the ElastiCache Redis replication group"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS worker nodes — granted access to Aurora and Redis"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS cluster's OIDC identity provider — used for IRSA role trust policies"
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "URL (without https://) of the EKS cluster's OIDC identity provider — used as the condition key in IRSA trust policies"
  type        = string
}

variable "aurora_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 4
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t4g.medium"
}

variable "redis_auth_token" {
  description = "AUTH token for the ElastiCache Redis replication group"
  type        = string
  sensitive   = true
}

variable "cognito_callback_urls" {
  description = "Allowed OAuth callback URLs for the Cognito app client"
  type        = list(string)
}

variable "cognito_logout_urls" {
  description = "Allowed OAuth logout URLs for the Cognito app client"
  type        = list(string)
}

variable "cognito_domain_prefix" {
  description = "Domain prefix for the Cognito hosted UI (e.g. 'compass-production' becomes compass-production.auth.us-east-1.amazoncognito.com)"
  type        = string
}

variable "ses_domain" {
  description = "Domain to verify with SES for transactional email"
  type        = string
}

# ── Kennari engine precedence test fixtures ───────────────────
# Not used by any Compass resource. Validate resolution order only.
# Full chain for this app: default → terraform.tfvars → baseline.auto.tfvars
#   → compass-config.tfvars → compass-env.tfvars

variable "test_precedence_tag" {
  description = "Kennari test fixture. Set at all five layers. Expected resolved value: 'env'."
  type        = string
  default     = "default"
}

variable "test_config_vs_env" {
  description = "Kennari test fixture. Set in config and env layers only. Expected resolved value: 'from-env'."
  type        = string
}

variable "test_environment_marker" {
  description = "Kennari test fixture. Set in compass-env.tfvars for production and dev with different values, to confirm the correct environment's file was evaluated. Expected: 'production-env' for production, 'dev-env' for dev."
  type        = string
}
