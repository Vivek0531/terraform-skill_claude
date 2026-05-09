output "vpc_id" {
  description = "Hub VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Hub VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of hub private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of hub public subnets"
  value       = aws_subnet.public[*].id
}

output "private_route_table_id" {
  description = "Primary private route table ID (used by TGW module to add spoke routes)"
  value       = aws_route_table.private[0].id
}

output "nat_public_ips" {
  description = "Elastic IPs allocated to NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}
