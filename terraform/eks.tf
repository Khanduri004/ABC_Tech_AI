data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

#Allow the eks.amazonaws.com service to assume this role"
data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project_name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = {
    Name        = "${var.project_name}-eks-cluster"
    Project     = var.project_name
    Environment = var.environment
  }
}

#attaches the official AWS-managed AmazonEKSClusterPolicy to that role.
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

#Allow ec2.amazonaws.com to assume this role".
data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project_name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = {
    Name        = "${var.project_name}-eks-node"
    Project     = var.project_name
    Environment = var.environment
  }
}

locals {
  eks_node_policies = {
    worker       = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    cni          = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    ecr_readonly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.eks_node_policies

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

#This creates the actual managed Kubernetes control plane (API Server, etcd).
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.k8s_version

  vpc_config {
    subnet_ids         = [for az in var.availability_zones : aws_subnet.public[az].id]
    security_group_ids = [aws_security_group.eks_nodes.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster
  ]

  tags = {
    Name        = var.cluster_name
    Project     = var.project_name
    Environment = var.environment
  }
}
#This provisions the worker EC2 instances (t3.micro) where your pods will run.
resource "aws_eks_node_group" "this" {
  cluster_name  = aws_eks_cluster.this.name
  node_role_arn = aws_iam_role.node.arn
  subnet_ids    = [for az in var.availability_zones : aws_subnet.public[az].id]

  instance_types = var.eks_node_instance_types

  scaling_config {
    desired_size = var.eks_desired_size
    min_size     = var.eks_min_size
    max_size     = var.eks_max_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.node
  ]

  tags = {
    Name        = "${var.project_name}-eks-node-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

#This enables IRSA (IAM Roles for Service Accounts).  
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name        = "${var.project_name}-eks-oidc"
    Project     = var.project_name
    Environment = var.environment
  }
}
