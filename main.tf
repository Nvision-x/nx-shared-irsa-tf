################################################################################
# Unified IRSA Module
# Supports all IRSA roles with enable flags
################################################################################

locals {
  oidc_hostpath = replace(var.oidc_issuer_url, "https://", "")
}

################################################################################
# 1. Bedrock IRSA
################################################################################

locals {
  # Provider prefix mapping
  bedrock_provider_prefixes = {
    anthropic = "anthropic."
    amazon    = "amazon."
    ai21      = "ai21."
    cohere    = "cohere."
    meta      = "meta."
    mistral   = "mistral."
    stability = "stability."
  }

  # Base allowed providers (either explicit allowlist or all providers)
  base_allowed_providers = length(var.bedrock_allowed_providers) > 0 ? var.bedrock_allowed_providers : keys(local.bedrock_provider_prefixes)

  # Final allowed providers after applying exclusions
  final_allowed_providers = [
    for provider in local.base_allowed_providers :
    provider if !contains(var.bedrock_excluded_providers, provider)
  ]

  # Generate model ARNs based on provider filtering
  bedrock_model_arns = var.bedrock_use_custom_model_arns ? var.bedrock_custom_model_arns : [
    for provider in local.final_allowed_providers :
    "arn:aws:bedrock:*::foundation-model/${local.bedrock_provider_prefixes[provider]}*"
  ]

  # Build policy statements based on capabilities
  bedrock_invoke_statement = contains(var.bedrock_capabilities, "invoke") ? [{
    Effect   = "Allow"
    Action   = ["bedrock:InvokeModel"]
    Resource = local.bedrock_model_arns
    Condition = {
      StringEquals = {
        "aws:RequestedRegion" = var.bedrock_allowed_regions
      }
    }
  }] : []

  bedrock_streaming_statement = contains(var.bedrock_capabilities, "streaming") ? [{
    Effect   = "Allow"
    Action   = ["bedrock:InvokeModelWithResponseStream"]
    Resource = local.bedrock_model_arns
    Condition = {
      StringEquals = {
        "aws:RequestedRegion" = var.bedrock_allowed_regions
      }
    }
  }] : []

  bedrock_model_catalog_statement = contains(var.bedrock_capabilities, "model_catalog") ? [{
    Effect = "Allow"
    Action = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel"
    ]
    Resource = "*"
  }] : []

  bedrock_agents_statement = contains(var.bedrock_capabilities, "agents") ? [{
    Effect = "Allow"
    Action = [
      "bedrock:InvokeAgent",
      "bedrock:Retrieve"
    ]
    Resource = var.bedrock_agent_arns
  }] : []

  bedrock_knowledge_bases_statement = contains(var.bedrock_capabilities, "knowledge_bases") ? [{
    Effect = "Allow"
    Action = [
      "bedrock:Retrieve",
      "bedrock:RetrieveAndGenerate"
    ]
    Resource = var.bedrock_knowledge_base_arns
  }] : []

  bedrock_guardrails_statement = contains(var.bedrock_capabilities, "guardrails") ? [{
    Effect = "Allow"
    Action = [
      "bedrock:ApplyGuardrail"
    ]
    Resource = var.bedrock_guardrail_arns
  }] : []

  # Combine all enabled statements
  bedrock_policy_statements = concat(
    local.bedrock_invoke_statement,
    local.bedrock_streaming_statement,
    local.bedrock_model_catalog_statement,
    local.bedrock_agents_statement,
    local.bedrock_knowledge_bases_statement,
    local.bedrock_guardrails_statement
  )
}

resource "aws_iam_policy" "bedrock" {
  count = var.enable_bedrock ? 1 : 0
  name  = "${var.cluster_name}-bedrock-access"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.bedrock_policy_statements
  })

  tags = var.tags
}

module "bedrock_irsa_role" {
  count   = var.enable_bedrock ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.58.0"

  role_name        = var.bedrock_role_name
  role_policy_arns = { bedrock = aws_iam_policy.bedrock[0].arn }

  oidc_providers = {
    eks = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = var.bedrock_service_accounts
    }
  }

  tags = var.tags
}

################################################################################
# 2. Postgres Backup IRSA (Dual Trust: RDS + OIDC)
################################################################################

data "aws_iam_policy_document" "postgres_backup_trust" {
  count = var.enable_postgres_backup ? 1 : 0

  # RDS service principal trust
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }

  # OIDC trust for EKS service accounts
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:${var.postgres_backup_namespace}:${var.postgres_backup_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "postgres_backup_policy" {
  count = var.enable_postgres_backup ? 1 : 0

  # S3 bucket permissions
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [var.postgres_s3_bucket_arn_pattern]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${var.postgres_s3_bucket_arn_pattern}/*"]
  }

  # RDS backup permissions
  statement {
    effect = "Allow"
    actions = [
      "rds:DescribeDBSnapshots",
      "rds:CreateDBSnapshot",
      "rds:DeleteDBSnapshot",
      "rds:ModifyDBSnapshotAttribute",
      "rds:DescribeDBInstances",
      "rds:CopyDBSnapshot"
    ]
    resources = [
      "arn:aws:rds:${var.postgres_region}:${var.postgres_account_id}:db:${var.postgres_db_identifier}",
      "arn:aws:rds:${var.postgres_region}:${var.postgres_account_id}:snapshot:*"
    ]
  }

  # KMS permissions
  statement {
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "rds.${var.postgres_region}.amazonaws.com",
        "s3.${var.postgres_region}.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "postgres_backup" {
  count              = var.enable_postgres_backup ? 1 : 0
  name               = var.postgres_backup_role_name
  assume_role_policy = data.aws_iam_policy_document.postgres_backup_trust[0].json
  tags               = var.tags
}

resource "aws_iam_policy" "postgres_backup" {
  count  = var.enable_postgres_backup ? 1 : 0
  name   = "${var.postgres_backup_role_name}-policy"
  policy = data.aws_iam_policy_document.postgres_backup_policy[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "postgres_backup" {
  count      = var.enable_postgres_backup ? 1 : 0
  role       = aws_iam_role.postgres_backup[0].name
  policy_arn = aws_iam_policy.postgres_backup[0].arn
}

################################################################################
# 3. EBS CSI Driver IRSA
################################################################################

data "aws_iam_policy" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0
  name  = "AmazonEBSCSIDriverPolicy"
}

data "aws_iam_policy_document" "ebs_csi_trust" {
  count = var.enable_ebs_csi ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:${var.ebs_csi_namespace}:${var.ebs_csi_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count              = var.enable_ebs_csi ? 1 : 0
  name               = var.ebs_csi_role_name
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.enable_ebs_csi ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = data.aws_iam_policy.ebs_csi[0].arn
}

################################################################################
# 4. Cluster Autoscaler IRSA (Scoped Policy)
################################################################################

resource "aws_iam_policy" "cluster_autoscaler" {
  count       = var.enable_cluster_autoscaler ? 1 : 0
  name        = "${var.cluster_name}-cluster-autoscaler"
  description = "Scoped permissions for EKS Cluster Autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ClusterAutoscalerDescribe"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeImages",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Sid    = "ClusterAutoscalerModify"
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
          }
        }
      }
    ]
  })

  tags = var.tags
}

module "cluster_autoscaler_irsa_role" {
  count   = var.enable_cluster_autoscaler ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.58.0"

  role_name        = var.cluster_autoscaler_role_name
  role_policy_arns = { autoscaling = aws_iam_policy.cluster_autoscaler[0].arn }

  oidc_providers = {
    eks = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.cluster_autoscaler_namespace}:${var.cluster_autoscaler_service_account}"]
    }
  }

  tags = var.tags
}

################################################################################
# 5. Load Balancer Controller IRSA
################################################################################

module "lb_controller_irsa_role" {
  count   = var.enable_lb_controller ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.58.0"

  role_name                              = var.lb_controller_role_name
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.lb_controller_namespace}:${var.lb_controller_service_account}"]
    }
  }

  tags = var.tags
}
