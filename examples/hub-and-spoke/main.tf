terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "hub-and-spoke/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Architecture = "hub-and-spoke"
      ManagedBy    = "terraform"
      Project      = var.project_name
    }
  }
}

# ── Hub VPC (shared services, egress, inspection) ──────────────────────────
module "hub_vpc" {
  source = "./modules/hub_vpc"

  name             = "${var.project_name}-hub"
  cidr             = var.hub_cidr
  azs              = var.availability_zones
  private_subnets  = var.hub_private_subnets
  public_subnets   = var.hub_public_subnets

  enable_nat_gateway = true
  single_nat_gateway = var.environment != "production"

  tags = local.common_tags
}

# ── Transit Gateway ────────────────────────────────────────────────────────
module "transit_gateway" {
  source = "./modules/transit_gateway"

  name            = "${var.project_name}-tgw"
  amazon_side_asn = var.tgw_asn

  hub_vpc_id         = module.hub_vpc.vpc_id
  hub_subnet_ids     = module.hub_vpc.private_subnet_ids
  hub_route_table_id = module.hub_vpc.private_route_table_id

  spoke_attachments = {
    for name, spoke in module.spoke_vpcs :
    name => {
      vpc_id         = spoke.vpc_id
      subnet_ids     = spoke.private_subnet_ids
      route_table_id = spoke.private_route_table_id
      environment    = var.spoke_vpcs[name].environment
    }
  }

  tags = local.common_tags
}

# ── Spoke VPCs ─────────────────────────────────────────────────────────────
module "spoke_vpcs" {
  source   = "./modules/spoke_vpc"
  for_each = var.spoke_vpcs

  name            = "${var.project_name}-${each.key}"
  cidr            = each.value.cidr
  azs             = var.availability_zones
  private_subnets = each.value.private_subnets
  environment     = each.value.environment

  tags = merge(local.common_tags, {
    Environment = each.value.environment
    SpokeName   = each.key
  })
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}
