output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The primary CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway."
  value       = module.vpc.igw_id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "List of private subnet IDs."
  value       = module.vpc.private_subnets
}

output "isolated_subnet_ids" {
  description = "List of isolated (database) subnet IDs."
  value       = module.vpc.database_subnets
}

output "public_subnet_ids_by_az" {
  description = "Map of availability zone to public subnet ID."
  value       = zipmap(var.availability_zones, module.vpc.public_subnets)
}

output "private_subnet_ids_by_az" {
  description = "Map of availability zone to private subnet ID."
  value       = zipmap(var.availability_zones, module.vpc.private_subnets)
}

output "isolated_subnet_ids_by_az" {
  description = "Map of availability zone to isolated subnet ID."
  value       = zipmap(var.availability_zones, module.vpc.database_subnets)
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs."
  value       = module.vpc.natgw_ids
}
