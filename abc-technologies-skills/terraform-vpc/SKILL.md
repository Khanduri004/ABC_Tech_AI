---
name: terraform-vpc
description: Writes Terraform for an AWS VPC — subnets, route tables, internet gateway, security groups — and exposes standardized outputs (vpc_id, subnet_ids, security_group_ids) for the terraform-eks and terraform-ec2 skills to consume. Use whenever the user needs AWS networking infra, a VPC module, or is provisioning EKS/EC2 and needs the underlying network first.
---

Build the VPC as its own self-contained module. Other stacks (EKS, EC2) reference its outputs — never duplicate VPC resources inside them.

## 1. Inputs
Expose as variables, don't hardcode: `cidr_block`, `availability_zones` (list), `public_subnet_cidrs` (list, one per AZ), `private_subnet_cidrs` (optional — omit entirely for a no-NAT-Gateway design), `project`/`environment` tags.

## 2. Core resources
- `aws_vpc` with the given CIDR, `enable_dns_support`/`enable_dns_hostnames` = true (required for EKS).
- `aws_subnet` — one per AZ via `for_each`/`count`, `map_public_ip_on_launch = true` for public subnets.
- `aws_internet_gateway` attached to the VPC.
- `aws_route_table` with a `0.0.0.0/0 -> igw` route, plus `aws_route_table_association` per public subnet.

## 3. No-NAT-Gateway pattern (cost-conscious default)
If the project doesn't need outbound-only private subnets, skip NAT Gateway entirely and use public subnets only, compensating with tight security groups (deny all inbound except explicitly needed ports/sources). Document this as a comment in the module — it's a deliberate cost/security tradeoff, not an oversight, and should be easy for a future reader to recognize as intentional.

## 4. Security groups
Define per-purpose, not one shared group: e.g. one SG for the CI/CD EC2 instance (SSH from a known IP, app ports), one for EKS worker nodes (node-to-node + control plane). Never default to `0.0.0.0/0` on anything other than genuinely public web ports.

## 5. EKS-required subnet tags
If subnets will host an EKS cluster, tag them so the cluster and load balancer controller can discover them:
```hcl
tags = {
  "kubernetes.io/cluster/<cluster-name>" = "shared"
  "kubernetes.io/role/elb"               = "1"   # public subnets
}
```

## 6. Outputs (the contract other skills rely on)
Always name these exactly so `terraform-eks` and `terraform-ec2` can consume them consistently:
- `vpc_id`
- `subnet_ids` (list)
- `security_group_ids` (map or list, keyed by purpose)

## 7. Consistent tagging
Apply `Name`, `Project`, `Environment` tags to every resource — this is what makes multi-stack `terraform destroy` and cost tracking manageable later.
