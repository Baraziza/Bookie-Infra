output "eks_cluster_role_arn" {
  description = "IAM Role ARN for the EKS Cluster"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "IAM Role ARN for the EKS Worker Nodes"
  value       = aws_iam_role.eks_node_role.arn
}
