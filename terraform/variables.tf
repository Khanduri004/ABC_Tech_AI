variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "project_name" {
  type    = string
  default = "abc-technologies"
}

variable "environment" {
  type    = string
  default = "dev"
}

# --- VPC ---

variable "cidr_block" {
  description = "IPv4 CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability Zones in which to create public subnets"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per availability zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "public_subnet_cidrs must contain exactly one CIDR for each availability zone."
  }
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into and access Jenkins on the CI/CD instance"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for subnet discovery tags"
  type        = string
  default     = "abc-technologies-eks"
}

# --- EKS ---

variable "k8s_version" {
  description = "Pinned Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.34"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for the managed node group; t3.micro is temporary for new-account limits"
  type        = list(string)
  default     = ["t3.micro"]
}

variable "eks_desired_size" {
  description = "Desired number of EKS worker nodes"
  type    = number
  default = 1
}

variable "eks_min_size" {
  description = "Minimum number of EKS worker nodes"
  type    = number
  default = 1
}

variable "eks_max_size" {
  description = "Maximum number of EKS worker nodes"
  type    = number
  default = 3
}

# --- EC2 (CI/CD box) ---

variable "ec2_instance_type" {
  description = "Sized for Jenkins + Docker + Maven running together — t3.small minimum, not free-tier t2.micro"
  type        = string
  default     = "t3.small"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 keypair for SSH access"
  type        = string
  default     = "abc-technologies-key"
}

variable "ec2_subnet_az" {
  description = "Availability Zone for the public CI/CD EC2 instance subnet"
  type        = string
  default     = "eu-west-1a"

  validation {
    condition     = contains(var.availability_zones, var.ec2_subnet_az)
    error_message = "ec2_subnet_az must be one of the configured availability_zones."
  }
}

variable "ec2_root_volume_size" {
  description = "Root EBS volume size in GiB for Jenkins, Docker, and Maven"
  type    = number
  default = 20
}
