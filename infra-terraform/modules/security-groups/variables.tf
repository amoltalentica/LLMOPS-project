variable "project" {
  description = "Short project name prefix"
  type        = string
}

variable "environment" {
  description = "Environment label"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC (used for intra-cluster rule)"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "Management CIDRs allowed SSH, Kubernetes API, RCA Agent, and ArgoCD access"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "Set at least one restricted management CIDR; 0.0.0.0/0 is not allowed."
  }
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
