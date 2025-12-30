################################################################################
# Unified Pod Identity Module
# Migrated from IRSA to EKS Pod Identity (AWS recommended approach)
################################################################################

################################################################################
# Common Trust Policy for Pod Identity
################################################################################

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

################################################################################
# 1. Bedrock Pod Identity
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

  # Parse bedrock service accounts into namespace:serviceaccount pairs
  bedrock_sa_pairs = var.enable_bedrock ? [
    for sa in var.bedrock_service_accounts : {
      namespace       = split(":", sa)[0]
      service_account = split(":", sa)[1]
    }
  ] : []
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

resource "aws_iam_role" "bedrock" {
  count              = var.enable_bedrock ? 1 : 0
  name               = var.bedrock_role_name
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "bedrock" {
  count      = var.enable_bedrock ? 1 : 0
  role       = aws_iam_role.bedrock[0].name
  policy_arn = aws_iam_policy.bedrock[0].arn
}

resource "aws_eks_pod_identity_association" "bedrock" {
  for_each = var.enable_bedrock ? { for idx, sa in local.bedrock_sa_pairs : "${sa.namespace}-${sa.service_account}" => sa } : {}

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.bedrock[0].arn

  tags = var.tags
}

################################################################################
# 2. Postgres Backup Pod Identity (Dual Trust: RDS + Pod Identity)
################################################################################

data "aws_iam_policy_document" "postgres_backup_trust" {
  count = var.enable_postgres_backup ? 1 : 0

  # RDS service principal trust (for RDS S3 export)
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }

  # Pod Identity trust for EKS pods
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
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

resource "aws_eks_pod_identity_association" "postgres_backup" {
  count = var.enable_postgres_backup ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.postgres_backup_namespace
  service_account = var.postgres_backup_service_account
  role_arn        = aws_iam_role.postgres_backup[0].arn

  tags = var.tags
}

################################################################################
# 3. EBS CSI Driver Pod Identity
################################################################################

data "aws_iam_policy" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0
  name  = "AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "ebs_csi" {
  count              = var.enable_ebs_csi ? 1 : 0
  name               = var.ebs_csi_role_name
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.enable_ebs_csi ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = data.aws_iam_policy.ebs_csi[0].arn
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.ebs_csi_namespace
  service_account = var.ebs_csi_service_account
  role_arn        = aws_iam_role.ebs_csi[0].arn

  tags = var.tags
}

################################################################################
# 4. Cluster Autoscaler Pod Identity
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

resource "aws_iam_role" "cluster_autoscaler" {
  count              = var.enable_cluster_autoscaler ? 1 : 0
  name               = var.cluster_autoscaler_role_name
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.enable_cluster_autoscaler ? 1 : 0
  role       = aws_iam_role.cluster_autoscaler[0].name
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.cluster_autoscaler_namespace
  service_account = var.cluster_autoscaler_service_account
  role_arn        = aws_iam_role.cluster_autoscaler[0].arn

  tags = var.tags
}

################################################################################
# 5. Load Balancer Controller Pod Identity
################################################################################

# Use the EKS-provided managed policy for LB Controller
data "aws_iam_policy" "lb_controller" {
  count = var.enable_lb_controller ? 1 : 0
  arn   = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

resource "aws_iam_role" "lb_controller" {
  count              = var.enable_lb_controller ? 1 : 0
  name               = var.lb_controller_role_name
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  count      = var.enable_lb_controller ? 1 : 0
  role       = aws_iam_role.lb_controller[0].name
  policy_arn = data.aws_iam_policy.lb_controller[0].arn
}

# Additional EC2 and WAF permissions needed for ALB Controller
resource "aws_iam_role_policy" "lb_controller_additional" {
  count = var.enable_lb_controller ? 1 : 0
  name  = "${var.lb_controller_role_name}-additional"
  role  = aws_iam_role.lb_controller[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:DescribeCoipPools",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeVpcEndpointServiceConfigurations",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  count = var.enable_lb_controller ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.lb_controller_namespace
  service_account = var.lb_controller_service_account
  role_arn        = aws_iam_role.lb_controller[0].arn

  tags = var.tags
}

################################################################################
# 6. Application S3 Access Pod Identity
################################################################################

locals {
  # Parse app S3 service accounts into namespace:serviceaccount pairs
  app_s3_sa_pairs = var.enable_app_s3_access ? [
    for sa in var.app_s3_service_accounts : {
      namespace       = split(":", sa)[0]
      service_account = split(":", sa)[1]
    }
  ] : []
}

data "aws_iam_policy_document" "app_s3_policy" {
  count = var.enable_app_s3_access ? 1 : 0

  # S3 bucket-level permissions
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [var.app_s3_bucket_arn_pattern]
  }

  # S3 object-level permissions
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${var.app_s3_bucket_arn_pattern}/*"]
  }
}

resource "aws_iam_policy" "app_s3" {
  count  = var.enable_app_s3_access ? 1 : 0
  name   = var.app_s3_role_name != "" ? "${var.app_s3_role_name}-policy" : "${var.cluster_name}-app-s3-access-policy"
  policy = data.aws_iam_policy_document.app_s3_policy[0].json
  tags   = var.tags
}

resource "aws_iam_role" "app_s3" {
  count              = var.enable_app_s3_access ? 1 : 0
  name               = var.app_s3_role_name != "" ? var.app_s3_role_name : "${var.cluster_name}-app-s3-access"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "app_s3" {
  count      = var.enable_app_s3_access ? 1 : 0
  role       = aws_iam_role.app_s3[0].name
  policy_arn = aws_iam_policy.app_s3[0].arn
}

resource "aws_eks_pod_identity_association" "app_s3" {
  for_each = var.enable_app_s3_access ? { for idx, sa in local.app_s3_sa_pairs : "${sa.namespace}-${sa.service_account}" => sa } : {}

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.app_s3[0].arn

  tags = var.tags
}
