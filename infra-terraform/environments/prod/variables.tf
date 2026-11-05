###############################################################################
# environments/prod/variables.tf
###############################################################################

#---------------------------------------
# Global
#---------------------------------------

variable "project" {
  description = "Short project name used as a prefix for all resources"
  type        = string
  default     = "ai-sre-agent"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "github_repo" {
  description = "GitHub repository (owner/repo) for OIDC and tagging"
  type        = string
  default     = "your-github-org/ai-sre-agent"
}

#---------------------------------------
# Network
#---------------------------------------

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "ssh_allowed_cidrs" {
  description = "Management CIDRs for SSH, Kubernetes API, RCA Agent, and ArgoCD. Use your IP (e.g. [\"1.2.3.4/32\"])."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "Set at least one restricted management CIDR; 0.0.0.0/0 is not allowed."
  }
}

#---------------------------------------
# Compute
#---------------------------------------

variable "k3s_instance_type" {
  description = "EC2 instance type for k3s. The default suits infrastructure experiments, not the full observability demo."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB; use at least 100 GB for the full observability demo."
  type        = number
  default     = 30
}

variable "k3s_version" {
  description = "k3s version (e.g. v1.30.2+k3s1). Empty = install latest."
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key material to create an EC2 key pair. Leave empty to skip."
  type        = string
  default     = ""
  sensitive   = true
}

#---------------------------------------
# IAM / OIDC
#---------------------------------------

variable "create_github_oidc_role" {
  type    = bool
  default = true
}

variable "create_github_oidc_provider" {
  description = "Whether to create the GitHub OIDC provider in IAM (set to false if your AWS account already has one)"
  type        = bool
  default     = true
}

variable "tfstate_bucket" {
  description = "S3 bucket name holding Terraform state (for GitHub Actions permissions)"
  type        = string
  default     = ""
}

variable "tflock_table" {
  description = "DynamoDB table name for state locking (for GitHub Actions permissions)"
  type        = string
  default     = ""
}

#---------------------------------------
# Application
#---------------------------------------

variable "ses_sender_email" {
  description = "Verified SES sender email address"
  type        = string
  default     = "alerts@example.com"
}

variable "ecr_repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["ai-sre-agent", "order-service", "product-service"]
}
