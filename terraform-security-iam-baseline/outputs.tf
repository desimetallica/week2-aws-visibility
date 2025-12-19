output "admin_group_users" {
  value = aws_iam_user_group_membership.alice_admin
}

output "developer_group_users" {
  value = aws_iam_user_group_membership.bob_developer
}

output "readonly_group_users" {
  value = aws_iam_user_group_membership.carol_readonly
}

output "carol_console_password" {
  description = "Initial password for carol's AWS Console login (if set by Terraform)."
  value       = aws_iam_user_login_profile.carol_console.password
  sensitive   = true
}

output "carol_console_login_url" {
  description = "AWS Console login URL for carol user."
  value = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}
