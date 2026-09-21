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

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into the CI/CD instance — tighten to your own IP before applying"
  type        = string
  default     = "0.0.0.0/0"
}

# --- EKS ---

variable "cluster_name" {
  type    = string
  default = "abc-technologies-eks"
}

variable "k8s_version" {
  type    = string
  default = "1.30"
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "eks_desired_size" {
  type    = number
  default = 2
}

variable "eks_min_size" {
  type    = number
  default = 1
}

variable "eks_max_size" {
  type    = number
  default = 3
}

# --- EC2 (CI/CD box) ---

variable "ec2_instance_type" {
  description = "Sized for Jenkins + Docker + Maven running together — t3.small minimum, not free-tier t2.micro"
  type        = string
  default     = "t3.small"
}

variable "ec2_key_name" {
  description = "Name of an existing EC2 keypair for SSH access"
  type        = string
  default     = "abc-technologies-key"
}

variable "ec2_root_volume_size" {
  type    = number
  default = 20
}

