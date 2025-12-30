################################################################################
# Bedrock Outputs
################################################################################

output "bedrock_iam_role_arn" {
  description = "Bedrock IAM role ARN"
  value       = var.enable_bedrock ? aws_iam_role.bedrock[0].arn : null
}

output "bedrock_iam_role_name" {
  description = "Bedrock IAM role name"
  value       = var.enable_bedrock ? aws_iam_role.bedrock[0].name : null
}

output "bedrock_iam_policy_arn" {
  description = "Bedrock IAM policy ARN"
  value       = var.enable_bedrock ? aws_iam_policy.bedrock[0].arn : null
}

output "bedrock_enabled_capabilities" {
  description = "List of enabled Bedrock capabilities"
  value       = var.enable_bedrock ? var.bedrock_capabilities : []
}

output "bedrock_enabled_providers" {
  description = "List of enabled Bedrock model providers (after filtering)"
  value       = var.enable_bedrock ? local.final_allowed_providers : []
}

output "bedrock_pod_identity_associations" {
  description = "Map of Bedrock Pod Identity associations"
  value       = var.enable_bedrock ? { for k, v in aws_eks_pod_identity_association.bedrock : k => v.id } : {}
}

################################################################################
# Postgres Backup Outputs
################################################################################

output "postgres_backup_iam_role_arn" {
  description = "Postgres backup IAM role ARN"
  value       = var.enable_postgres_backup ? aws_iam_role.postgres_backup[0].arn : null
}

output "postgres_backup_iam_role_name" {
  description = "Postgres backup IAM role name"
  value       = var.enable_postgres_backup ? aws_iam_role.postgres_backup[0].name : null
}

output "postgres_backup_iam_policy_arn" {
  description = "Postgres backup IAM policy ARN"
  value       = var.enable_postgres_backup ? aws_iam_policy.postgres_backup[0].arn : null
}

output "postgres_backup_pod_identity_association_id" {
  description = "Postgres backup Pod Identity association ID"
  value       = var.enable_postgres_backup ? aws_eks_pod_identity_association.postgres_backup[0].id : null
}

################################################################################
# EBS CSI Driver Outputs
################################################################################

output "ebs_csi_iam_role_arn" {
  description = "EBS CSI IAM role ARN"
  value       = var.enable_ebs_csi ? aws_iam_role.ebs_csi[0].arn : null
}

output "ebs_csi_iam_role_name" {
  description = "EBS CSI IAM role name"
  value       = var.enable_ebs_csi ? aws_iam_role.ebs_csi[0].name : null
}

output "ebs_csi_pod_identity_association_id" {
  description = "EBS CSI Pod Identity association ID"
  value       = var.enable_ebs_csi ? aws_eks_pod_identity_association.ebs_csi[0].id : null
}

################################################################################
# Cluster Autoscaler Outputs
################################################################################

output "cluster_autoscaler_iam_role_arn" {
  description = "Cluster Autoscaler IAM role ARN"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].arn : null
}

output "cluster_autoscaler_iam_role_name" {
  description = "Cluster Autoscaler IAM role name"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].name : null
}

output "cluster_autoscaler_iam_policy_arn" {
  description = "Cluster Autoscaler IAM policy ARN"
  value       = var.enable_cluster_autoscaler ? aws_iam_policy.cluster_autoscaler[0].arn : null
}

output "cluster_autoscaler_pod_identity_association_id" {
  description = "Cluster Autoscaler Pod Identity association ID"
  value       = var.enable_cluster_autoscaler ? aws_eks_pod_identity_association.cluster_autoscaler[0].id : null
}

################################################################################
# Load Balancer Controller Outputs
################################################################################

output "lb_controller_iam_role_arn" {
  description = "Load Balancer Controller IAM role ARN"
  value       = var.enable_lb_controller ? aws_iam_role.lb_controller[0].arn : null
}

output "lb_controller_iam_role_name" {
  description = "Load Balancer Controller IAM role name"
  value       = var.enable_lb_controller ? aws_iam_role.lb_controller[0].name : null
}

output "lb_controller_pod_identity_association_id" {
  description = "Load Balancer Controller Pod Identity association ID"
  value       = var.enable_lb_controller ? aws_eks_pod_identity_association.lb_controller[0].id : null
}
