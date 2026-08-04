terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ──────────────────────────────────────────────
# KMS — customer-managed key for all data at rest
# ──────────────────────────────────────────────

resource "aws_kms_key" "compass" {
  description             = "Compass client portal — CMK for all resources"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_kms_alias" "compass" {
  name          = "alias/compass-key"
  target_key_id = aws_kms_key.compass.key_id
}

# ──────────────────────────────────────────────
# Cognito — client identity
# ──────────────────────────────────────────────

resource "aws_cognito_user_pool" "clients" {
  name = "compass-clients"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_cognito_user_pool_client" "portal" {
  name         = "compass-portal-client"
  user_pool_id = aws_cognito_user_pool.clients.id

  generate_secret                     = true
  allowed_oauth_flows                 = ["code"]
  allowed_oauth_scopes                = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  access_token_validity  = 15
  id_token_validity      = 15
  refresh_token_validity = 7
}

resource "aws_cognito_user_pool_domain" "portal" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.clients.id
}

# ──────────────────────────────────────────────
# Aurora PostgreSQL — account and session data
# ──────────────────────────────────────────────

resource "aws_rds_cluster" "compass" {
  cluster_identifier      = "compass-${var.environment}"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = "15.4"
  database_name           = "compass"
  master_username          = "compass_admin"
  manage_master_user_password = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.compass.arn

  backup_retention_period = 14
  preferred_backup_window = "03:00-04:00"

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  vpc_security_group_ids = [aws_security_group.compass_db.id]
  db_subnet_group_name   = var.db_subnet_group_name

  deletion_protection = true

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier = aws_rds_cluster.compass.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.compass.engine
  engine_version     = aws_rds_cluster.compass.engine_version

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_security_group" "compass_db" {
  name        = "compass-db-${var.environment}"
  description = "Aurora access for Compass services"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

# ──────────────────────────────────────────────
# ElastiCache Redis — session cache
# ──────────────────────────────────────────────

resource "aws_elasticache_replication_group" "compass" {
  replication_group_id = "compass-session-${var.environment}"
  description           = "Compass client session cache"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.redis_node_type

  num_cache_clusters = 2
  automatic_failover_enabled = true

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                  = var.redis_auth_token
  kms_key_id                  = aws_kms_key.compass.arn

  subnet_group_name = var.elasticache_subnet_group_name
  security_group_ids = [aws_security_group.compass_redis.id]

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_security_group" "compass_redis" {
  name        = "compass-redis-${var.environment}"
  description = "Redis access for Compass services"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

# ──────────────────────────────────────────────
# S3 — statements, message attachments, static assets
# ──────────────────────────────────────────────

resource "aws_s3_bucket" "statements" {
  bucket = "${var.resource_prefix}-compass-statements"

  tags = {
    Application = "compass"
    Tier        = "2"
    DataClass   = "client-pii"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "statements" {
  bucket = aws_s3_bucket.statements.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.compass.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "statements" {
  bucket                  = aws_s3_bucket.statements.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "statements" {
  bucket = aws_s3_bucket.statements.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "attachments" {
  bucket = "${var.resource_prefix}-compass-attachments"

  tags = {
    Application = "compass"
    Tier        = "2"
    DataClass   = "client-pii"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.compass.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "attachments" {
  bucket                  = aws_s3_bucket.attachments.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.resource_prefix}-compass-static-assets"

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket                  = aws_s3_bucket.static_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "static_assets_cloudfront" {
  bucket = aws_s3_bucket.static_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_assets.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.portal.arn
          }
        }
      }
    ]
  })
}

# ──────────────────────────────────────────────
# CloudFront + WAF — public-facing portal
# ──────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "static_assets" {
  name                              = "compass-static-assets-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_wafv2_web_acl" "portal" {
  name  = "compass-portal-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "compass-rate-limit"
      sampled_requests_enabled    = true
    }
  }

  rule {
    name     = "aws-managed-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "compass-common-rules"
      sampled_requests_enabled    = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                 = "compass-portal-waf"
    sampled_requests_enabled    = true
  }

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_cloudfront_distribution" "portal" {
  enabled             = true
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.portal.arn

  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = "compass-static-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_assets.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "compass-static-assets"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

# ──────────────────────────────────────────────
# SES — transactional email
# ──────────────────────────────────────────────

resource "aws_ses_domain_identity" "compass" {
  domain = var.ses_domain
}

resource "aws_ses_domain_dkim" "compass" {
  domain = aws_ses_domain_identity.compass.domain
}

# ──────────────────────────────────────────────
# SQS / SNS — notification pipeline
# ──────────────────────────────────────────────

resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "compass-notifications-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = aws_kms_key.compass.arn

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_sqs_queue" "notifications" {
  name                       = "compass-notifications"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  kms_master_key_id          = aws_kms_key.compass.arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_sns_topic" "client_notifications" {
  name              = "compass-client-notifications"
  kms_master_key_id = aws_kms_key.compass.arn

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

# ──────────────────────────────────────────────
# Secrets Manager
# ──────────────────────────────────────────────

resource "aws_secretsmanager_secret" "cognito" {
  name       = "compass/${var.environment}/cognito-client-secret"
  kms_key_id = aws_kms_key.compass.arn

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_secretsmanager_secret_version" "cognito" {
  secret_id     = aws_secretsmanager_secret.cognito.id
  secret_string = aws_cognito_user_pool_client.portal.client_secret
}

resource "aws_secretsmanager_secret" "db" {
  name       = "compass/${var.environment}/db-credentials"
  kms_key_id = aws_kms_key.compass.arn

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

# ──────────────────────────────────────────────
# IAM — IRSA roles, one per Helm chart
# Tier 2: scoped narrowly per the IAM Governance Policy.
# Each role trusts only its own Kubernetes ServiceAccount.
#
# portal-bff: synchronous client-facing path (auth, accounts/holdings)
# portal-workers: async path (statements, messaging, notifications)
# ──────────────────────────────────────────────

resource "aws_iam_role" "portal_bff" {
  name = "compass-portal-bff-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.eks_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.eks_oidc_provider_url}:sub" = "system:serviceaccount:compass:portal-bff"
        }
      }
    }]
  })

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_iam_role_policy" "portal_bff" {
  name = "compass-portal-bff-policy"
  role = aws_iam_role.portal_bff.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CognitoAccess"
        Effect   = "Allow"
        Action   = ["cognito-idp:InitiateAuth", "cognito-idp:GetUser", "cognito-idp:RespondToAuthChallenge"]
        Resource = aws_cognito_user_pool.clients.arn
      },
      {
        Sid      = "CognitoSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.cognito.arn
      },
      {
        Sid      = "DBSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Sid      = "KMSAccess"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.compass.arn
      }
    ]
  })
}

resource "aws_iam_role" "portal_workers" {
  name = "compass-portal-workers-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.eks_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.eks_oidc_provider_url}:sub" = "system:serviceaccount:compass:portal-workers"
        }
      }
    }]
  })

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_iam_role_policy" "portal_workers" {
  name = "compass-portal-workers-policy"
  role = aws_iam_role.portal_workers.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StatementsBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.statements.arn}/*"
      },
      {
        Sid      = "AttachmentsBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.attachments.arn}/*"
      },
      {
        Sid      = "SQSConsume"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.notifications.arn
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.client_notifications.arn
      },
      {
        Sid      = "SESSend"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = aws_ses_domain_identity.compass.arn
      },
      {
        Sid      = "DBSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Sid      = "KMSAccess"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.compass.arn
      }
    ]
  })
}


resource "aws_cloudwatch_log_group" "compass" {
  name              = "/compass/${var.environment}/application"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.compass.arn

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}

resource "aws_cloudwatch_metric_alarm" "notifications_dlq_depth" {
  alarm_name          = "compass-notifications-dlq-depth-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Compass notification DLQ has messages — client notifications may be failing to deliver"
  alarm_actions       = [aws_sns_topic.client_notifications.arn]

  dimensions = {
    QueueName = aws_sqs_queue.notifications_dlq.name
  }

  tags = {
    Application = "compass"
    Tier        = "2"
  }
}
