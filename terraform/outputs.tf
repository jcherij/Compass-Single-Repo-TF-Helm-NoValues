output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for the Compass client identity"
  value       = aws_cognito_user_pool.clients.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID — used by auth-bff"
  value       = aws_cognito_user_pool_client.portal.id
}

output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.compass.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.compass.reader_endpoint
}

output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint address"
  value       = aws_elasticache_replication_group.compass.primary_endpoint_address
}

output "statements_bucket" {
  description = "S3 bucket name for client statements"
  value       = aws_s3_bucket.statements.id
}

output "attachments_bucket" {
  description = "S3 bucket name for message attachments"
  value       = aws_s3_bucket.attachments.id
}

output "static_assets_bucket" {
  description = "S3 bucket name for portal static assets"
  value       = aws_s3_bucket.static_assets.id
}

output "cloudfront_distribution_domain" {
  description = "CloudFront distribution domain name for the portal"
  value       = aws_cloudfront_distribution.portal.domain_name
}

output "notifications_queue_url" {
  description = "SQS queue URL for client notifications"
  value       = aws_sqs_queue.notifications.url
}

output "client_notifications_topic_arn" {
  description = "SNS topic ARN for client notification delivery"
  value       = aws_sns_topic.client_notifications.arn
}

output "portal_bff_role_arn" {
  description = "IAM role ARN for the portal-bff service account (IRSA)"
  value       = aws_iam_role.portal_bff.arn
}

output "portal_workers_role_arn" {
  description = "IAM role ARN for the portal-workers service account (IRSA)"
  value       = aws_iam_role.portal_workers.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for all Compass encryption at rest"
  value       = aws_kms_key.compass.arn
}
