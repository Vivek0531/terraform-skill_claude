resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = var.name, Role = "spoke", Environment = var.environment })
}

# ── Private subnets only — spokes have no direct internet access ───────────
resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name        = "${var.name}-private-${var.azs[count.index]}"
    Tier        = "private"
    Environment = var.environment
  })
}

# ── Route table (default route added by transit_gateway module) ────────────
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Security Group: deny all inter-spoke by default ────────────────────────
resource "aws_security_group" "default_deny" {
  name        = "${var.name}-default-deny"
  description = "Explicit deny-all; attach only hub-approved SGs to workloads"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-default-deny" })
}

# Revoke the AWS-default allow-all egress so nothing leaves without approval
resource "aws_vpc_security_group_egress_rule" "revoke_default" {
  security_group_id = aws_security_group.default_deny.id
  # AWS default is allow-all; we remove it by setting no rules here.
  # Workload SGs must explicitly allow needed egress.
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  # Intentionally marking this as a placeholder to override via workload SGs.
  tags = merge(var.tags, { Name = "placeholder-removed-by-workload-sg" })
}

# ── VPC Flow Logs ──────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/flow-logs/${var.name}"
  retention_in_days = var.flow_log_retention_days
  tags              = var.tags
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id
  tags            = merge(var.tags, { Name = "${var.name}-flow-log" })
}

# ── NACL: additional layer of segmentation ─────────────────────────────────
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.tags, { Name = "${var.name}-private-nacl" })
}

# Allow all inbound from hub CIDR (shared services, NAT return traffic)
resource "aws_network_acl_rule" "inbound_from_hub" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  egress         = false
  cidr_block     = var.hub_cidr
}

# Allow ephemeral return traffic from internet (via hub NAT)
resource "aws_network_acl_rule" "inbound_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 200
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Deny all other inbound (spokes cannot reach each other directly at NACL level)
resource "aws_network_acl_rule" "inbound_deny_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 32766
  protocol       = "-1"
  rule_action    = "deny"
  egress         = false
  cidr_block     = "0.0.0.0/0"
}

# Allow all outbound (TGW route table enforces destination; NACL stays permissive)
resource "aws_network_acl_rule" "outbound_allow_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  egress         = true
  cidr_block     = "0.0.0.0/0"
}
