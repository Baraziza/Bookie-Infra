variable "aws_region" {
  description = "The AWS region where resources will be created"
  type        = string
}

variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default = "Bookie-eks"
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for EKS"
  type        = list(string)
}

variable "eks_cluster_role_arn" {
  description = "IAM Role ARN for EKS Cluster"
  type        = string
}
