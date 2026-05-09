output "vpc_id" {
  description = "Spoke VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Spoke VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of spoke private subnets"
  value       = aws_subnet.private[*].id
}

output "private_route_table_id" {
  description = "Route table ID for TGW module to inject the default route"
  value       = aws_route_table.private.id
}

output "default_deny_sg_id" {
  description = "Security Group ID of the default-deny SG"
  value       = aws_security_group.default_deny.id
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}
