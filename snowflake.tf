# snowflake.tf

# Confirm provider connectivity
data "snowflake_current_account" "this" {}

output "snowflake_current_account" {
  description = "Account locator of the Snowflake account Terraform is connected to"
  value       = data.snowflake_current_account.this.account
}

############################################
# snowflake.tf — WIF role, user, and grants
############################################

# 0) Pick the AWS role ARN to bind as the workload identity:
#    - If var.aws_wif_role_arn is provided, use it
#    - Otherwise, default to the EC2 instance role ARN we created in iam.tf
locals {
  wif_role_arn_effective = (
    var.aws_wif_role_arn != "" ? var.aws_wif_role_arn : aws_iam_role.ec2.arn
  )
}

# 1) Create the WIF test role in Snowflake
resource "snowflake_account_role" "wif_test_role" {
  name    = var.wif_role_name
  comment = "Role for AWS→Snowflake WIF test user (Terraform-managed)"
}

# 2) Create the WIF service user using the native snowflake_service_user resource
resource "snowflake_service_user" "wif" {
  name              = var.wif_user_name
  default_role      = snowflake_account_role.wif_test_role.name
  default_warehouse = var.wif_default_warehouse
  comment           = "WIF service user (AWS role mapped) managed by Terraform"

  default_workload_identity {
    aws {
      arn = local.wif_role_arn_effective
    }
  }
}

# 3) Grant the WIF role to the WIF user
resource "snowflake_grant_account_role" "wif_role_to_user" {
  role_name = snowflake_account_role.wif_test_role.name
  user_name = snowflake_service_user.wif.name
}

# --- Optional: minimal usage grants so the user can run a quick query ---
# Guard each with count so nulls skip creation.

resource "snowflake_grant_privileges_to_account_role" "wif_wh_usage" {
  count             = var.wif_default_warehouse == null ? 0 : 1
  account_role_name = snowflake_account_role.wif_test_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.wif_default_warehouse
  }
}

resource "snowflake_grant_privileges_to_account_role" "wif_db_usage" {
  count             = var.wif_test_database == null ? 0 : 1
  account_role_name = snowflake_account_role.wif_test_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = var.wif_test_database
  }
}

resource "snowflake_grant_privileges_to_account_role" "wif_schema_usage" {
  count             = var.wif_test_schema == null ? 0 : 1
  account_role_name = snowflake_account_role.wif_test_role.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${var.wif_test_database}.${var.wif_test_schema}"
  }
}


