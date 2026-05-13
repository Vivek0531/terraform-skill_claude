variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_groups" {
  description = "EKS managed node group configurations"
  type        = any
  default     = {}
}

variable "enable_cluster_autoscaler" {
  type    = bool
  default = true
}

variable "enable_aws_load_balancer_controller" {
  type    = bool
  default = true
}

variable "enable_ebs_csi_driver" {
  type    = bool
  default = true
}
