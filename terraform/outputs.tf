output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "Public subnet IDs keyed by availability zone"
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "public_subnet_ids" {
  description = "Public subnet IDs as a list, for consumers that need list input"
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "security_group_ids" {
  description = "Security group IDs keyed by purpose"
  value = {
    ci_server = aws_security_group.ci_server.id
    eks_nodes = aws_security_group.eks_nodes.id
  }
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint for the EKS cluster"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster CA data"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "node_group_name" {
  description = "Name of the managed EKS node group"
  value       = aws_eks_node_group.this.node_group_name
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider associated with EKS"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}

output "ci_server_instance_id" {
  description = "ID of the Jenkins and Docker CI/CD EC2 instance"
  value       = aws_instance.ci_server.id
}

output "ci_server_public_ip" {
  description = "Public IPv4 address of the CI/CD EC2 instance"
  value       = aws_instance.ci_server.public_ip
}

output "ci_server_public_dns" {
  description = "Public DNS name of the CI/CD EC2 instance"
  value       = aws_instance.ci_server.public_dns
}

output "ci_server_iam_role_arn" {
  description = "ARN of the IAM role attached to the CI/CD EC2 instance"
  value       = aws_iam_role.ci_server.arn
}
