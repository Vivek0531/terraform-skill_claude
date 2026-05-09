variable "name" {
  description = "Name prefix for Transit Gateway resources"
  type        = string
}

variable "amazon_side_asn" {
  description = "BGP ASN for the Transit Gateway"
  type        = number
  default     = 64512
}

variable "hub_vpc_id" {
  description = "VPC ID of the hub (shared-services) VPC"
  type        = string
}

variable "hub_subnet_ids" {
  description = "Subnet IDs in the hub VPC for TGW attachment (one per AZ)"
  type        = list(string)
}

variable "hub_route_table_id" {
  description = "Route table ID in the hub VPC to add routes toward spokes"
  type        = string
}

variable "spoke_attachments" {
  description = "Map of spoke VPC attachment details"
  type = map(object({
    vpc_id         = string
    subnet_ids     = list(string)
    route_table_id = string
    environment    = string
  }))
}

variable "tags" {
  description = "Tags to apply to all Transit Gateway resources"
  type        = map(string)
  default     = {}
}
