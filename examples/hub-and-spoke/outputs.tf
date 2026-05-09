output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = module.transit_gateway.tgw_id
}

output "transit_gateway_arn" {
  description = "ARN of the Transit Gateway (use for RAM sharing across accounts)"
  value       = module.transit_gateway.tgw_arn
}

output "hub_vpc_id" {
  description = "ID of the hub (shared-services) VPC"
  value       = module.hub_vpc.vpc_id
}

output "hub_vpc_cidr" {
  description = "CIDR block of the hub VPC"
  value       = module.hub_vpc.vpc_cidr
}

output "spoke_vpc_ids" {
  description = "Map of spoke name → VPC ID"
  value       = { for name, spoke in module.spoke_vpcs : name => spoke.vpc_id }
}

output "spoke_vpc_cidrs" {
  description = "Map of spoke name → VPC CIDR"
  value       = { for name, spoke in module.spoke_vpcs : name => spoke.vpc_cidr }
}

output "tgw_hub_route_table_id" {
  description = "TGW route table ID used by the hub VPC attachment"
  value       = module.transit_gateway.hub_route_table_id
}

output "tgw_spoke_route_table_id" {
  description = "TGW route table ID used by all spoke VPC attachments"
  value       = module.transit_gateway.spoke_route_table_id
}

output "nat_gateway_public_ips" {
  description = "Elastic IPs of NAT Gateways in the hub (whitelist these on external SaaS)"
  value       = module.hub_vpc.nat_public_ips
}
