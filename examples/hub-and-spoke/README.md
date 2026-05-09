# Hub-and-Spoke VPC Architecture with AWS Transit Gateway

A production-ready Terraform implementation of hub-and-spoke network topology using AWS Transit Gateway. Provides centralized egress, shared services, and strict east-west traffic segmentation across unlimited VPCs.

---

## Architecture Diagram

```
                              INTERNET
                                 │
                         ┌───────▼───────┐
                         │  Internet GW  │
                         └───────┬───────┘
                                 │
            ┌────────────────────▼──────────────────────────────┐
            │               HUB VPC (10.0.0.0/16)               │
            │                   [Shared Services]                │
            │                                                    │
            │  ┌─────────────┐        ┌─────────────────────┐   │
            │  │ Public Nets │        │    Private Nets      │   │
            │  │10.0.101.0/24│        │   10.0.1-3.0/24     │   │
            │  │10.0.102.0/24│        │                      │   │
            │  │10.0.103.0/24│        │  - Shared Services   │   │
            │  │  NAT GW x3  │        │  - DNS Resolvers     │   │
            │  └─────────────┘        │  - Security Tools    │   │
            │                         │  - Monitoring        │   │
            └─────────────────────────┬────────────────────-─┘
                                      │  TGW Attachment
                         ┌────────────▼────────────┐
                         │   Transit Gateway (TGW)  │
                         │   ASN: 64512             │
                         │                          │
                         │  ┌──────────────────┐    │
                         │  │  Hub Route Table │    │  ← Sees all spoke CIDRs
                         │  │  (hub attachment)│    │    via propagation
                         │  └──────────────────┘    │
                         │  ┌──────────────────┐    │
                         │  │ Spoke Route Table│    │  ← Default 0.0.0.0/0
                         │  │(all spokes share)│    │    points to hub
                         │  └──────────────────┘    │
                         └────────────┬────────────-┘
              ┌───────────────────────┼──────────────────────────┐
              │                       │                          │
   ┌──────────▼──────┐    ┌──────────▼──────┐    ┌─────────────▼─────┐
   │  PROD VPC       │    │  STAGING VPC    │    │  DEV VPC           │
   │  10.1.0.0/16    │    │  10.2.0.0/16    │    │  10.3.0.0/16      │
   │                 │    │                 │    │                    │
   │  Private only   │    │  Private only   │    │  Private only      │
   │  No IGW         │    │  No IGW         │    │  No IGW            │
   │  NACL: deny     │    │  NACL: deny     │    │  NACL: deny        │
   │  direct spoke   │    │  direct spoke   │    │  direct spoke      │
   └─────────────────┘    └─────────────────┘    └────────────────────┘

       ┌────────────────────────────────────────────────┐
       │                SECURITY VPC  10.4.0.0/16       │
       │  (IDS/IPS, SIEM, Network Firewall, Bastion)    │
       └────────────────────────────────────────────────┘

Traffic flow examples:
  Dev → Internet:   Dev VPC → TGW (spoke RT: 0.0.0.0/0 → hub) → Hub NAT GW → Internet
  Dev → Prod:       Dev VPC → TGW (spoke RT: 0.0.0.0/0 → hub) → Hub SG/FW → TGW → Prod
  Security → Any:   Security VPC → TGW (hub RT: propagated routes) → any spoke
```

---

## Why Hub-and-Spoke Solves Multi-VPC Challenges

### The Problem: Mesh Networking Doesn't Scale

When organizations grow beyond 5-10 VPCs, the naive approach (VPC Peering mesh) breaks down:

| VPCs | Peering connections needed | Manual route entries |
|------|---------------------------|---------------------|
| 5    | 10                        | 50+                 |
| 10   | 45                        | 450+                |
| 20   | 190                       | 3,800+              |
| 50   | 1,225                     | 60,000+             |

VPC peering is also non-transitive — traffic from VPC A cannot reach VPC C through VPC B — requiring every pair to have a direct connection.

### How Hub-and-Spoke Fixes It

| Problem | Hub-and-Spoke Solution |
|---------|------------------------|
| Quadratic peering growth | One TGW attachment per VPC → O(n) connections |
| Non-transitive routing | TGW is fully transitive; hub routes to any spoke |
| Duplicate NAT Gateways in every VPC | Single NAT fleet in hub; all spokes share it |
| Inconsistent DNS across VPCs | Centralized Route 53 Resolver endpoints in hub |
| Blind spots in east-west traffic | All spoke-to-spoke traffic traverses hub for inspection |
| Per-VPC firewall sprawl | One AWS Network Firewall or appliance fleet in hub |
| Security team visibility | Centralized flow logs and SIEM ingestion from hub |
| Cross-account connectivity | TGW shared via AWS RAM; same model across accounts |

### Security Segmentation Model

```
 Spoke RT (all spokes)          Hub RT
 ┌──────────────────┐           ┌─────────────────────────────────┐
 │ 0.0.0.0/0 → hub │           │ 10.1.0.0/16 → prod-attachment   │
 │ (hub propagated) │           │ 10.2.0.0/16 → staging-attach   │
 └──────────────────┘           │ 10.3.0.0/16 → dev-attachment    │
                                 │ 10.4.0.0/16 → security-attach  │
                                 └─────────────────────────────────┘

Spoke-to-spoke traffic path:
  Dev (10.3.x) ──► TGW ──► Hub firewall ──► TGW ──► Prod (10.1.x)
                    ↑                                        ↑
           Spoke RT forwards                       Hub RT forwards
           all traffic to hub                   to specific spoke

Blocked by default (NACL rule 32766 deny-all on spokes):
  Dev (10.3.x) ──✗──► Prod (10.3.x) [no direct spoke-to-spoke path]
```

**Layers of defence:**
1. **TGW Route Tables** — spokes share a route table with only a `0.0.0.0/0 → hub` entry; no direct spoke-to-spoke routes exist
2. **NACLs** — spoke subnets explicitly deny inbound from non-hub CIDRs at layer 3
3. **Security Groups** — workloads must opt-in to allow traffic; default-deny SG ships with each spoke
4. **Hub inspection** — AWS Network Firewall / 3rd-party appliance placed in hub intercepts all east-west flows

---

## Step-by-Step Deployment Guide

### Prerequisites

| Requirement | Version |
|-------------|---------|
| Terraform | ≥ 1.6 |
| AWS CLI | ≥ 2.x |
| AWS Provider | ≥ 5.0 |
| IAM permissions | See [required IAM permissions](#required-iam-permissions) |

### Step 1 — Bootstrap Remote State

```bash
# Create S3 bucket for state (one-time)
aws s3api create-bucket \
  --bucket my-terraform-state-bucket \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket my-terraform-state-bucket \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket my-terraform-state-bucket \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB lock table
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Step 2 — Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your CIDR ranges and project name.
# Ensure no CIDR blocks overlap across hub and all spokes.
```

**CIDR planning rules:**
- Hub: `10.0.0.0/16` (reserve this for shared services)
- Each spoke gets a unique `/16` from `10.1.0.0` onward
- Spoke `/24` subnets must not overlap with hub or other spokes
- Leave room for future spoke VPCs (plan for 2× current count)

### Step 3 — Initialize and Plan

```bash
terraform init
terraform validate
terraform plan -out=tfplan
```

Review the plan for:
- Correct number of TGW attachments (one per VPC)
- Two TGW route tables (hub + spoke)
- Route propagations in both directions
- NAT Gateway count matches your HA requirements

### Step 4 — Apply in Dependency Order

TGW attachments must exist before routes can reference them. Terraform handles this automatically via `depends_on`, but apply all at once:

```bash
terraform apply tfplan
```

Expected resource creation order:
1. VPCs and subnets (hub + spokes)
2. Internet Gateway, NAT Gateways (hub)
3. Route tables (VPC-level)
4. Transit Gateway
5. TGW VPC attachments (hub, then spokes)
6. TGW route tables and associations
7. Route propagations
8. Static routes in TGW route tables
9. VPC-level routes pointing to TGW

### Step 5 — Validate Connectivity

```bash
# Confirm TGW route tables are populated
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <spoke-rt-id> \
  --filters "Name=type,Values=static,propagated"

# Test from a spoke instance — should reach internet via hub NAT IP
# (hub NAT EIP will appear as the source IP)
curl -s https://checkip.amazonaws.com

# Test spoke-to-spoke is blocked (from dev instance, try to reach prod)
# Should time out at NACL / Security Group, not route through directly
```

### Step 6 — Add Security Inspection (Recommended)

Place AWS Network Firewall in hub private subnets and insert it between TGW and the hub route table:

```hcl
# In modules/hub_vpc — add after NAT gateway section
resource "aws_networkfirewall_firewall" "inspection" {
  name                = "${var.name}-nfw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = aws_vpc.this.id

  dynamic "subnet_mapping" {
    for_each = aws_subnet.private[*].id
    content { subnet_id = subnet_mapping.value }
  }
}
```

Then update the hub route table to send spoke-bound traffic through the firewall endpoints before forwarding to TGW.

### Step 7 — Cross-Account Expansion (Optional)

Share the Transit Gateway to other AWS accounts via Resource Access Manager:

```hcl
resource "aws_ram_resource_share" "tgw" {
  name                      = "${var.name}-tgw-share"
  allow_external_principals = false  # org-only sharing
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = module.transit_gateway.tgw_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "org" {
  principal          = "arn:aws:organizations::ACCOUNT_ID:organization/ORG_ID"
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
```

Each account then creates a TGW attachment to the shared TGW and associates it with the spoke route table. The routing model is identical to single-account.

---

## Module Reference

### `modules/hub_vpc`

| Input | Type | Description |
|-------|------|-------------|
| `name` | string | Resource name prefix |
| `cidr` | string | Hub VPC CIDR |
| `azs` | list(string) | AZs for subnet placement |
| `private_subnets` | list(string) | Private subnet CIDRs |
| `public_subnets` | list(string) | Public subnet CIDRs (NAT) |
| `enable_nat_gateway` | bool | Create NAT Gateway(s) |
| `single_nat_gateway` | bool | One NAT vs one-per-AZ |

### `modules/spoke_vpc`

| Input | Type | Description |
|-------|------|-------------|
| `name` | string | Resource name prefix |
| `cidr` | string | Spoke VPC CIDR |
| `private_subnets` | list(string) | Private subnet CIDRs |
| `environment` | string | Environment label |
| `hub_cidr` | string | Hub CIDR (NACL allow rule) |

### `modules/transit_gateway`

| Input | Type | Description |
|-------|------|-------------|
| `hub_vpc_id` | string | Hub VPC to attach |
| `hub_subnet_ids` | list(string) | Hub subnets for attachment |
| `hub_route_table_id` | string | Hub RT to receive spoke routes |
| `spoke_attachments` | map(object) | Map of spoke VPC details |
| `amazon_side_asn` | number | BGP ASN (64512–65534) |

---

## Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*RouteTable*",
        "ec2:*Route*", "ec2:*InternetGateway*",
        "ec2:*NatGateway*", "ec2:*TransitGateway*",
        "ec2:*NetworkAcl*", "ec2:*SecurityGroup*",
        "ec2:*FlowLog*", "ec2:AllocateAddress",
        "ec2:ReleaseAddress", "ec2:DescribeAvailabilityZones",
        "logs:*", "iam:CreateRole", "iam:PutRolePolicy",
        "iam:AttachRolePolicy", "iam:PassRole",
        "ram:*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Azure and GCP Equivalents

This pattern translates directly to other clouds:

### Azure (Hub-and-Spoke with Azure Virtual WAN)

```hcl
# Hub = Azure Virtual WAN Hub
resource "azurerm_virtual_wan" "this" { ... }
resource "azurerm_virtual_hub" "this" {
  virtual_wan_id = azurerm_virtual_wan.this.id
  address_prefix = "10.0.0.0/23"  # WAN hub needs /23 minimum
}

# Spoke = VNet connected to WAN hub (replaces TGW attachment)
resource "azurerm_virtual_hub_connection" "spoke" {
  for_each               = var.spoke_vnets
  virtual_hub_id         = azurerm_virtual_hub.this.id
  remote_virtual_network_id = each.value.vnet_id
  internet_security_enabled = true  # force internet through hub
}
```

Key difference: Azure Virtual WAN uses BGP route propagation automatically; route tables are simpler but less granular than TGW route tables.

### GCP (Hub-and-Spoke with Network Connectivity Center)

```hcl
# Hub = NCC Hub
resource "google_network_connectivity_hub" "this" {
  name = var.name
}

# Spokes = VPC Network spoke attached to NCC hub
resource "google_network_connectivity_spoke" "spokes" {
  for_each = var.spoke_vpcs
  hub      = google_network_connectivity_hub.this.id
  location = "global"

  linked_vpc_network {
    uri                  = each.value.network_self_link
    exclude_export_ranges = ["0.0.0.0/0"]  # block full-mesh if needed
  }
}
```

Key difference: GCP NCC supports data plane isolation via `exclude_export_ranges` at the hub level rather than separate route tables.

---

## Cost Considerations

| Resource | Cost driver | Optimization |
|----------|-------------|--------------|
| Transit Gateway | $0.05/hr + $0.02/GB data | One TGW per region is sufficient |
| TGW attachments | $0.05/hr per attachment | Minimize attachment count with RAM sharing |
| NAT Gateway | $0.045/hr + $0.045/GB | `single_nat_gateway = true` for non-prod |
| VPC Flow Logs | CloudWatch ingestion + storage | Use S3 destination for lower cost at scale |

For most organizations with ≥4 VPCs, hub-and-spoke with a single TGW + centralized NAT is cheaper than per-VPC NAT Gateways even before accounting for engineering time saved.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Spoke → internet fails | Default route missing in spoke VPC RT | Check `aws_route.spokes_default` created |
| Spoke A → Spoke B fails | Expected — blocked by design | Route through hub firewall intentionally |
| Hub → spoke fails | Propagation missing | Verify `aws_ec2_transit_gateway_route_table_propagation.spokes_to_hub` |
| TGW attachment pending | IAM or quota issue | Check service quota for TGW attachments per region |
| DNS not resolving cross-VPC | DNS support disabled | Ensure `dns_support = "enable"` on TGW attachment |
