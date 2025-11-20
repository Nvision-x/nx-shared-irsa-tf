# nx-shared-irsa-modules

Unified Terraform module for all IAM Roles for Service Accounts (IRSA) used across both `nx-iam-tf` and `nx-infra-tf` deployment patterns.

## Overview

This module consolidates all IRSA role creation into a single, configurable module with enable flags for each role type. It eliminates code duplication between the two deployment patterns:

1. **Full Auto Deployment**: All resources (EKS + IAM) managed in `nx-infra-tf`
2. **IAM Separation**: IAM roles managed separately in `nx-iam-tf` for customer environments requiring separation

## Architecture Benefits

### Before Refactoring
- **~800+ lines** of duplicated IRSA code across both modules
- Separate files for each IRSA role type
- Maintenance burden: Changes required in multiple locations
- Risk of configuration drift

### After Refactoring
- **~350 lines** in single unified module (56% reduction)
- Single source of truth with enable flags
- Consistent behavior across deployment patterns
- Easy to enable/disable specific roles
- Simplified maintenance

## Supported IRSA Roles

### 1. Bedrock (`enable_bedrock`)
Amazon Bedrock access with capability and provider filtering.

**Features**:
- Capability control: `invoke`, `streaming`, `model_catalog`, `agents`, `knowledge_bases`, `guardrails`
- Provider filtering: allowlist/blocklist for model providers (anthropic, amazon, ai21, cohere, meta, mistral, stability)
- Custom model ARNs support
- Regional restrictions

### 2. Postgres Backup (`enable_postgres_backup`)
PostgreSQL/RDS backup with dual trust (RDS service principal + OIDC).

**Features**:
- S3 backup storage permissions
- RDS snapshot management
- KMS encryption support
- Dual trust policy for both RDS and EKS access

### 3. EBS CSI Driver (`enable_ebs_csi`)
EBS CSI Driver using AWS managed policy.

**Features**:
- Uses AWS managed `AmazonEBSCSIDriverPolicy`
- Standard configuration for kube-system namespace

### 4. Cluster Autoscaler (`enable_cluster_autoscaler`)
Scoped cluster autoscaler with tag-based permissions.

**Features**:
- Read permissions: Describe ASG, instances, launch configs
- Write permissions: SetDesiredCapacity, TerminateInstance
- **Tag-based scoping**: Only resources tagged with `k8s.io/cluster-autoscaler/${cluster_name} = owned`
- More secure than AWS managed `AutoScalingFullAccess`

### 5. Load Balancer Controller (`enable_lb_controller`)
AWS Load Balancer Controller using AWS managed policy.

**Features**:
- Uses terraform-aws-modules with managed LBC policy
- Standard configuration for kube-system namespace

---

## Usage

### Full Auto Deployment (nx-infra-tf)

```hcl
module "irsa" {
  source = "../nx-shared-irsa-modules"
  count  = var.enable_irsa ? 1 : 0

  # Common parameters (from EKS module)
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  cluster_name      = var.cluster_name

  # Enable specific roles
  enable_bedrock            = var.enable_bedrock_irsa
  enable_postgres_backup    = var.enable_postgres
  enable_ebs_csi           = true
  enable_cluster_autoscaler = true
  enable_lb_controller      = true

  # Bedrock-specific configuration
  bedrock_role_name        = var.bedrock_role_name
  bedrock_service_accounts = var.bedrock_service_accounts
  bedrock_capabilities     = var.bedrock_capabilities
  # ... other bedrock vars

  # Postgres-specific configuration
  postgres_backup_role_name  = "${var.db_identifier}-backup-role"
  postgres_db_identifier     = var.db_identifier
  postgres_region            = var.region
  postgres_account_id        = data.aws_caller_identity.current.account_id
  # ... other postgres vars

  # EBS CSI, Autoscaler, LBC configurations
  ebs_csi_role_name                  = "${var.cluster_name}-ebs-csi-irsa"
  cluster_autoscaler_role_name       = var.autoscaler_role_name
  lb_controller_role_name            = var.lb_controller_role_name

  tags = var.tags
}
```

### IAM Separation (nx-iam-tf)

```hcl
module "irsa" {
  source = "../nx-shared-irsa-modules"
  count  = var.enable_irsa ? 1 : 0

  # Common parameters (from local OIDC provider)
  oidc_provider_arn = aws_iam_openid_connect_provider.oidc_provider[0].arn
  oidc_issuer_url   = var.oidc_issuer_url
  cluster_name      = var.cluster_name

  # Enable specific roles
  enable_bedrock            = var.enable_bedrock_access
  enable_postgres_backup    = var.enable_postgres
  enable_ebs_csi           = true
  enable_cluster_autoscaler = true
  enable_lb_controller      = true

  # Role-specific configurations (same as above)
  # ...

  tags = var.tags
}
```

---

## Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `oidc_provider_arn` | OIDC provider ARN for IRSA | string |
| `oidc_issuer_url` | OIDC issuer URL | string |
| `cluster_name` | EKS cluster name | string |

## Enable Flags (All Default to `false`)

| Flag | Description |
|------|-------------|
| `enable_bedrock` | Enable Bedrock IRSA role |
| `enable_postgres_backup` | Enable Postgres Backup IRSA role |
| `enable_ebs_csi` | Enable EBS CSI Driver IRSA role |
| `enable_cluster_autoscaler` | Enable Cluster Autoscaler IRSA role |
| `enable_lb_controller` | Enable Load Balancer Controller IRSA role |

## Role-Specific Variables

Each role has its own set of configuration variables. See `variables.tf` for complete list.

### Bedrock Variables
- `bedrock_role_name` - IAM role name
- `bedrock_service_accounts` - List of namespace:serviceaccount pairs
- `bedrock_capabilities` - List of capabilities to enable
- `bedrock_excluded_providers` - Providers to block
- `bedrock_allowed_providers` - Providers to allow
- And more...

### Postgres Backup Variables
- `postgres_backup_role_name` - IAM role name
- `postgres_db_identifier` - RDS database identifier
- `postgres_backup_namespace` - K8s namespace
- `postgres_backup_service_account` - K8s service account
- `postgres_region` - AWS region
- `postgres_account_id` - AWS account ID
- `postgres_s3_bucket_arn_pattern` - S3 bucket pattern

### EBS CSI Variables
- `ebs_csi_role_name` - IAM role name
- `ebs_csi_namespace` - K8s namespace (default: kube-system)
- `ebs_csi_service_account` - K8s service account (default: ebs-csi-controller-sa)

### Cluster Autoscaler Variables
- `cluster_autoscaler_role_name` - IAM role name
- `cluster_autoscaler_namespace` - K8s namespace (default: kube-system)
- `cluster_autoscaler_service_account` - K8s service account (default: cluster-autoscaler)

### Load Balancer Controller Variables
- `lb_controller_role_name` - IAM role name
- `lb_controller_namespace` - K8s namespace (default: kube-system)
- `lb_controller_service_account` - K8s service account (default: aws-load-balancer-controller)

---

## Outputs

All outputs are conditional based on enable flags. If a role is not enabled, its output will be `null`.

### Bedrock Outputs
- `bedrock_iam_role_arn` - Role ARN
- `bedrock_iam_policy_arn` - Policy ARN
- `bedrock_enabled_capabilities` - List of enabled capabilities
- `bedrock_enabled_providers` - List of allowed providers

### Postgres Backup Outputs
- `postgres_backup_iam_role_arn` - Role ARN
- `postgres_backup_iam_role_name` - Role name
- `postgres_backup_iam_policy_arn` - Policy ARN

### EBS CSI Outputs
- `ebs_csi_iam_role_arn` - Role ARN
- `ebs_csi_iam_role_name` - Role name

### Cluster Autoscaler Outputs
- `cluster_autoscaler_iam_role_arn` - Role ARN
- `cluster_autoscaler_iam_policy_arn` - Policy ARN

### Load Balancer Controller Outputs
- `lb_controller_iam_role_arn` - Role ARN

---

## Deployment Patterns

### Pattern 1: Full Auto Deployment

Everything created in `nx-infra-tf`, including OIDC provider and IRSA roles.

**Flow**:
1. Deploy `nx-infra-tf` with `enable_irsa = true`
2. All IRSA roles created automatically

**OIDC Source**: `module.eks.oidc_provider_arn` and `module.eks.cluster_oidc_issuer_url`

### Pattern 2: IAM Separation

IAM roles managed separately in `nx-iam-tf` after EKS cluster creation.

**Flow**:
1. Deploy `nx-iam-tf` with `enable_irsa = false`
2. Deploy `nx-infra-tf` (creates EKS cluster with OIDC provider)
3. Extract `oidc_issuer_url` from `nx-infra-tf` outputs
4. Redeploy `nx-iam-tf` with `enable_irsa = true` and `oidc_issuer_url` set

**OIDC Source**: `aws_iam_openid_connect_provider.oidc_provider[0].arn` and `var.oidc_issuer_url`

---

## Code Savings

| Component | Before (lines) | After (lines) | Savings |
|-----------|---------------|---------------|---------|
| nx-iam-tf IRSA files | 420 | 63 | 357 (85%) |
| nx-infra-tf IRSA files | 420 | 63 | 357 (85%) |
| Shared module | 0 | 350 | -350 |
| **Total** | **840** | **476** | **364 (43%)** |

Additionally:
- Single point of maintenance
- No risk of configuration drift
- Easier to add new IRSA roles
- Consistent behavior across deployments

---

## Security Notes

### Cluster Autoscaler - Scoped vs Wide Permissions

This module uses the **scoped cluster autoscaler** policy from `nx-iam-tf`, not the wide `AutoScalingFullAccess` policy from `nx-infra-tf`.

**Scoped Policy (Used Here)**:
- Read permissions: All ASG/EC2 describe operations
- Write permissions: Only resources tagged with `k8s.io/cluster-autoscaler/${cluster_name} = owned`
- More secure, prevents accidental scaling of unrelated ASGs

**Wide Policy (Not Used)**:
- Uses AWS managed `AutoScalingFullAccess`
- Can modify any ASG in the account
- Faster to deploy, but less secure

**Recommendation**: Use scoped policy for production, wide policy only for dev/test environments where speed matters more than security.

---

## Adding New IRSA Roles

To add a new IRSA role type to this module:

1. **Add enable flag** in `variables.tf`:
   ```hcl
   variable "enable_new_role" {
     description = "Enable New Role IRSA"
     type        = bool
     default     = false
   }
   ```

2. **Add role-specific variables** in `variables.tf`

3. **Add role resources** in `main.tf`:
   ```hcl
   resource "aws_iam_policy" "new_role" {
     count = var.enable_new_role ? 1 : 0
     # ... policy definition
   }

   module "new_role_irsa" {
     count  = var.enable_new_role ? 1 : 0
     source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
     # ... role configuration
   }
   ```

4. **Add outputs** in `outputs.tf`:
   ```hcl
   output "new_role_iam_role_arn" {
     value = var.enable_new_role ? module.new_role_irsa[0].iam_role_arn : null
   }
   ```

5. **Update parent modules** to pass new variables and use new outputs

---

## Troubleshooting

### Issue: Module not found

**Solution**:
```bash
cd /path/to/nx-iam-tf  # or nx-infra-tf
terraform init
```

### Issue: No roles being created

**Symptoms**: `terraform plan` shows no IRSA resources

**Solution**: Check that:
1. `enable_irsa = true` in parent module
2. At least one `enable_*` flag is `true` in module call
3. OIDC provider exists and ARN is correct

### Issue: Role exists but pods can't assume it

**Symptoms**: Pod errors like "AccessDenied" or "Not authorized"

**Solution**: Verify:
1. Service account annotation has correct role ARN
2. Namespace:serviceaccount matches what's configured in module
3. OIDC trust policy has correct issuer URL
4. Pod is using the annotated service account

---

## Version History

- **v2.0.0** (2025-01-20): Unified module with enable flags
  - Consolidated all 5 IRSA roles into single module
  - Added scoped cluster autoscaler policy
  - Eliminated 364 lines of duplicate code
  - Simplified maintenance and updates

- **v1.0.0** (2025-01-20): Initial release with separate modules
  - bedrock-irsa module
  - postgres-backup-irsa module
  - ebs-csi-irsa module
