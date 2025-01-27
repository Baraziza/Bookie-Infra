output "nodegroup_id" {
  description = "EKS Node Group ID"
  value       = aws_eks_node_group.eks_nodes.id
}

output "nodegroup_arn" {
  description = "EKS Node Group ARN"
  value       = aws_eks_node_group.eks_nodes.arn
}
