################################################################################
# Bedrock Outputs
################################################################################

output "bedrock_iam_role_arn" {
  description = "Bedrock IRSA role ARN"
  value       = var.enable_bedrock ? module.bedrock_irsa_role[0].iam_role_arn : null
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

################################################################################
# Postgres Backup Outputs
################################################################################

output "postgres_backup_iam_role_arn" {
  description = "Postgres backup IRSA role ARN"
  value       = var.enable_postgres_backup ? aws_iam_role.postgres_backup[0].arn : null
}

output "postgres_backup_iam_role_name" {
  description = "Postgres backup IRSA role name"
  value       = var.enable_postgres_backup ? aws_iam_role.postgres_backup[0].name : null
}

output "postgres_backup_iam_policy_arn" {
  description = "Postgres backup IAM policy ARN"
  value       = var.enable_postgres_backup ? aws_iam_policy.postgres_backup[0].arn : null
}

################################################################################
# EBS CSI Driver Outputs
################################################################################

output "ebs_csi_iam_role_arn" {
  description = "EBS CSI IRSA role ARN"
  value       = var.enable_ebs_csi ? aws_iam_role.ebs_csi[0].arn : null
}

output "ebs_csi_iam_role_name" {
  description = "EBS CSI IRSA role name"
  value       = var.enable_ebs_csi ? aws_iam_role.ebs_csi[0].name : null
}

################################################################################
# Cluster Autoscaler Outputs
################################################################################

output "cluster_autoscaler_iam_role_arn" {
  description = "Cluster Autoscaler IRSA role ARN"
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler_irsa_role[0].iam_role_arn : null
}

output "cluster_autoscaler_iam_policy_arn" {
  description = "Cluster Autoscaler IAM policy ARN"
  value       = var.enable_cluster_autoscaler ? aws_iam_policy.cluster_autoscaler[0].arn : null
}

################################################################################
# Load Balancer Controller Outputs
################################################################################

output "lb_controller_iam_role_arn" {
  description = "Load Balancer Controller IRSA role ARN"
  value       = var.enable_lb_controller ? module.lb_controller_irsa_role[0].iam_role_arn : null
}
