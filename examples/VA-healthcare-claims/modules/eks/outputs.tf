output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "cluster_autoscaler_role_arn" {
  value = try(module.cluster_autoscaler_irsa[0].iam_role_arn, "")
}

output "aws_lb_controller_role_arn" {
  value = try(module.aws_lb_controller_irsa[0].iam_role_arn, "")
}
