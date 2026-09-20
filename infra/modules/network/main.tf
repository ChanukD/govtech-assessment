data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Tier offsets of 0, 10 and 20 leave each tier room to grow to ten AZs before the
  # ranges would collide, so adding an AZ never renumbers existing subnets.
  public_subnets   = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, var.subnet_newbits, i) }
  private_subnets  = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, var.subnet_newbits, i + 10) }
  isolated_subnets = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, var.subnet_newbits, i + 20) }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Both are required for the interface endpoints' private DNS to resolve.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  # The ALB gets its public addresses from the load balancer itself, so nothing here
  # needs an automatic public IP.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name = "${var.name_prefix}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_subnet" "isolated" {
  for_each = local.isolated_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name = "${var.name_prefix}-isolated-${each.key}"
    Tier = "isolated"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# One route table per tier rather than per AZ. Per-AZ tables only earn their keep once
# there is a per-AZ NAT gateway to point at, and this design has none.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

# No routes are ever added here: the database tier reaches nothing outside the VPC.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-isolated-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "isolated" {
  for_each = aws_subnet.isolated

  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}

# S3 is reached through a gateway endpoint, which is free and needs no ENI. Only the
# private tier gets the route: the worker reads the source bucket, the database does not.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.name_prefix}-s3-endpoint"
  }
}

# Created here because it belongs to the endpoints, but deliberately left without
# rules: the security module owns those so they can reference the task security groups
# by ID rather than by CIDR.
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-vpc-endpoints"
  description = "Interface VPC endpoints. Ingress rules are managed by the security module."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-vpc-endpoints"
  }
}

# These replace a NAT gateway. Without them the private tier could not pull images,
# ship logs, read secrets or reach SQS.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_endpoint_services

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-${replace(each.key, ".", "-")}-endpoint"
  }
}
