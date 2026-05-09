# ── Transit Gateway ────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway" "this" {
  description                     = "Hub-and-spoke Transit Gateway for ${var.name}"
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "disable"   # require explicit acceptance
  default_route_table_association = "disable"   # use custom route tables
  default_route_table_propagation = "disable"   # control propagation explicitly
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, { Name = var.name })
}

# ── Hub attachment ─────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = var.hub_vpc_id
  subnet_ids                                      = var.hub_subnet_ids
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"

  tags = merge(var.tags, { Name = "${var.name}-hub-attachment", Role = "hub" })
}

# ── Spoke attachments ──────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_vpc_attachment" "spokes" {
  for_each = var.spoke_attachments

  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = each.value.vpc_id
  subnet_ids                                      = each.value.subnet_ids
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"

  tags = merge(var.tags, {
    Name        = "${var.name}-${each.key}-attachment"
    Role        = "spoke"
    Environment = each.value.environment
  })
}

# ── TGW Route Tables ───────────────────────────────────────────────────────
# Hub route table: receives propagations from ALL spokes → hub sees all CIDRs
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(var.tags, { Name = "${var.name}-hub-rt" })
}

# Spoke route table: default route points to hub; spokes cannot reach each other
# directly (traffic must traverse the hub for inspection).
resource "aws_ec2_transit_gateway_route_table" "spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(var.tags, { Name = "${var.name}-spokes-rt" })
}

# ── Route Table Associations ───────────────────────────────────────────────
resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spokes" {
  for_each = aws_ec2_transit_gateway_vpc_attachment.spokes

  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

# ── Route Propagations ─────────────────────────────────────────────────────
# Each spoke propagates its CIDR into the hub route table so hub can route back
resource "aws_ec2_transit_gateway_route_table_propagation" "spokes_to_hub" {
  for_each = aws_ec2_transit_gateway_vpc_attachment.spokes

  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

# Hub propagates its CIDR into the spoke route table so spokes can return traffic
resource "aws_ec2_transit_gateway_route_table_propagation" "hub_to_spokes" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

# ── Static default route in spoke RT → hub ─────────────────────────────────
# All inter-spoke and internet-bound traffic from spokes goes to the hub first.
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

# ── VPC Route Table updates ────────────────────────────────────────────────
# Hub VPC: route RFC-1918 space toward TGW (so it can reach spokes)
resource "aws_route" "hub_to_spokes" {
  for_each = toset(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])

  route_table_id         = var.hub_route_table_id
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# Spoke VPCs: default route to TGW so internet and cross-VPC traffic goes to hub
resource "aws_route" "spokes_default" {
  for_each = var.spoke_attachments

  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spokes]
}
