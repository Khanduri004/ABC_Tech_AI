---
name: terraform-eks
description: Writes Terraform for an AWS EKS cluster and managed node group, consuming vpc_id/subnet_ids from the terraform-vpc skill rather than duplicating networking. Use whenever the user is provisioning a Kubernetes cluster on AWS, setting up an EKS node group, or wiring IAM roles for EKS.
---

Never redefine VPC/subnet resources here — reference the `terraform-vpc` module's outputs (`vpc_id`, `subnet_ids`), whether via `module.vpc.subnet_ids` in the same root module or remote state if the VPC lives in a separate state file.

## 1. IAM roles (two separate roles, don't merge them)
- **Cluster role**: trust policy for `eks.amazonaws.com`, attach `AmazonEKSClusterPolicy`.
- **Node group role**: trust policy for `ec2.amazonaws.com`, attach `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`.

## 2. Cluster
```hcl
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.k8s_version   # pin explicitly, don't leave default

  vpc_config {
    subnet_ids = var.subnet_ids   # from terraform-vpc output
  }
}
```

## 3. Managed node group
```hcl
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }
}
```

## 4. New-account / free-tier capacity gotcha
New AWS accounts can be restricted to free-tier instance types only, which will reject `t3.medium`+ node groups with a quota error that looks like a permissions issue. If the node group creation fails on instance type:
- Check for a "free tier only" service quota restriction (lifts automatically after ~24h, or can be raised via a support case).
- Fall back to a free-tier-eligible type (`t3.micro`) temporarily and note it as a known temporary substitution, not a final sizing decision.

## 5. Outputs
- `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`
- Remind the user of the kubeconfig command after apply: `aws eks update-kubeconfig --name <cluster_name> --region <region>`

## 6. Cost reminder
EKS control plane + node group both bill continuously. Flag to the user that this is one of the higher-cost pieces of the stack and worth `terraform destroy`-ing at the end of a work session if not actively needed.
