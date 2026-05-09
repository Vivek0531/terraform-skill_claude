output "tgw_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "tgw_arn" {
  description = "Transit Gateway ARN (use with AWS RAM for cross-account sharing)"
  value       = aws_ec2_transit_gateway.this.arn
}

output "hub_attachment_id" {
  description = "TGW attachment ID for the hub VPC"
  value       = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

output "spoke_attachment_ids" {
  description = "Map of spoke name → TGW attachment ID"
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.spokes : k => v.id }
}

output "hub_route_table_id" {
  description = "TGW route table ID associated with the hub attachment"
  value       = aws_ec2_transit_gateway_route_table.hub.id
}

output "spoke_route_table_id" {
  description = "TGW route table ID associated with all spoke attachments"
  value       = aws_ec2_transit_gateway_route_table.spokes.id
}
