variable "aws_region" {
  description = "AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "admin_user_name" {
  description = "Name of the admin user."
  type        = string
  default     = "alice"
}

variable "developer_user_name" {
  description = "Name of the developer user."
  type        = string
  default     = "bob"
}

variable "readonly_user_name" {
  description = "Name of the read-only user."
  type        = string
  default     = "carol"
}

variable "admin_group_name" {
  description = "Name of the admin group."
  type        = string
  default     = "admins"
}

variable "developer_group_name" {
  description = "Name of the developer group."
  type        = string
  default     = "developers"
}

variable "readonly_group_name" {
  description = "Name of the read-only group."
  type        = string
  default     = "readonly"
}
