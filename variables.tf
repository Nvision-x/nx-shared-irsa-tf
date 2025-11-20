################################################################################
# Common Variables
################################################################################

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA (from nx-iam-tf or nx-infra-tf)"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL (used for trust policy conditions)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Enable Flags
################################################################################

variable "enable_bedrock" {
  description = "Enable Bedrock IRSA role"
  type        = bool
  default     = false
}

variable "enable_postgres_backup" {
  description = "Enable Postgres Backup IRSA role"
  type        = bool
  default     = false
}

variable "enable_ebs_csi" {
  description = "Enable EBS CSI Driver IRSA role"
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler IRSA role"
  type        = bool
  default     = false
}

variable "enable_lb_controller" {
  description = "Enable Load Balancer Controller IRSA role"
  type        = bool
  default     = false
}

################################################################################
# Bedrock Variables
################################################################################

variable "bedrock_role_name" {
  description = "Name of IAM role for Bedrock access"
  type        = string
  default     = ""
}

variable "bedrock_service_accounts" {
  description = "List of namespace:serviceaccount pairs for Bedrock access"
  type        = list(string)
  default     = []
}

variable "bedrock_capabilities" {
  description = "List of Bedrock capabilities to enable"
  type        = list(string)
  default     = ["invoke", "streaming", "model_catalog"]

  validation {
    condition = alltrue([
      for cap in var.bedrock_capabilities :
      contains(["invoke", "streaming", "model_catalog", "agents", "knowledge_bases", "guardrails"], cap)
    ])
    error_message = "Invalid capability. Valid options: invoke, streaming, model_catalog, agents, knowledge_bases, guardrails"
  }
}

variable "bedrock_excluded_providers" {
  description = "List of model providers to EXCLUDE from access"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for provider in var.bedrock_excluded_providers :
      contains(["anthropic", "amazon", "ai21", "cohere", "meta", "mistral", "stability"], provider)
    ])
    error_message = "Invalid provider. Valid options: anthropic, amazon, ai21, cohere, meta, mistral, stability"
  }
}

variable "bedrock_allowed_providers" {
  description = "List of model providers to ALLOW. If empty, all providers are allowed (except excluded ones)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for provider in var.bedrock_allowed_providers :
      contains(["anthropic", "amazon", "ai21", "cohere", "meta", "mistral", "stability"], provider)
    ])
    error_message = "Invalid provider. Valid options: anthropic, amazon, ai21, cohere, meta, mistral, stability"
  }
}

variable "bedrock_use_custom_model_arns" {
  description = "Use custom model ARNs instead of auto-generated ARNs"
  type        = bool
  default     = false
}

variable "bedrock_custom_model_arns" {
  description = "Custom list of Bedrock model ARNs"
  type        = list(string)
  default     = ["arn:aws:bedrock:*::foundation-model/*"]
}

variable "bedrock_allowed_regions" {
  description = "List of AWS regions where Bedrock API calls are allowed"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "bedrock_agent_arns" {
  description = "List of Bedrock Agent ARNs"
  type        = list(string)
  default     = ["arn:aws:bedrock:*:*:agent/*"]
}

variable "bedrock_knowledge_base_arns" {
  description = "List of Bedrock Knowledge Base ARNs"
  type        = list(string)
  default     = ["arn:aws:bedrock:*:*:knowledge-base/*"]
}

variable "bedrock_guardrail_arns" {
  description = "List of Bedrock Guardrail ARNs"
  type        = list(string)
  default     = ["arn:aws:bedrock:*:*:guardrail/*"]
}

################################################################################
# Postgres Backup Variables
################################################################################

variable "postgres_backup_role_name" {
  description = "Name of IAM role for Postgres backup"
  type        = string
  default     = ""
}

variable "postgres_db_identifier" {
  description = "Database identifier for RDS resource ARNs"
  type        = string
  default     = ""
}

variable "postgres_backup_namespace" {
  description = "Kubernetes namespace for backup service account"
  type        = string
  default     = "default"
}

variable "postgres_backup_service_account" {
  description = "Kubernetes service account name for backup"
  type        = string
  default     = "postgres-backup"
}

variable "postgres_region" {
  description = "AWS region for RDS and S3 resources"
  type        = string
  default     = ""
}

variable "postgres_account_id" {
  description = "AWS account ID for resource ARNs"
  type        = string
  default     = ""
}

variable "postgres_s3_bucket_arn_pattern" {
  description = "S3 bucket ARN pattern for backup storage"
  type        = string
  default     = "arn:aws:s3:::nvisionx*"
}

################################################################################
# EBS CSI Driver Variables
################################################################################

variable "ebs_csi_role_name" {
  description = "Name of IAM role for EBS CSI Driver"
  type        = string
  default     = ""
}

variable "ebs_csi_namespace" {
  description = "Kubernetes namespace for EBS CSI Driver"
  type        = string
  default     = "kube-system"
}

variable "ebs_csi_service_account" {
  description = "Kubernetes service account for EBS CSI Driver"
  type        = string
  default     = "ebs-csi-controller-sa"
}

################################################################################
# Cluster Autoscaler Variables
################################################################################

variable "cluster_autoscaler_role_name" {
  description = "Name of IAM role for Cluster Autoscaler"
  type        = string
  default     = ""
}

variable "cluster_autoscaler_namespace" {
  description = "Kubernetes namespace for Cluster Autoscaler"
  type        = string
  default     = "kube-system"
}

variable "cluster_autoscaler_service_account" {
  description = "Kubernetes service account for Cluster Autoscaler"
  type        = string
  default     = "cluster-autoscaler"
}

################################################################################
# Load Balancer Controller Variables
################################################################################

variable "lb_controller_role_name" {
  description = "Name of IAM role for Load Balancer Controller"
  type        = string
  default     = ""
}

variable "lb_controller_namespace" {
  description = "Kubernetes namespace for Load Balancer Controller"
  type        = string
  default     = "kube-system"
}

variable "lb_controller_service_account" {
  description = "Kubernetes service account for Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}
