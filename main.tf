terraform {
  required_version = ">= 1.2.0"
}

module "networking" {
  source              = "./modules/networking"
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name        = var.cluster_name
}

module "iam" {
  source           = "./modules/iam"
  aws_region       = var.aws_region
  cluster_name     = var.cluster_name
}

module "eks" {
  source              = "./modules/eks"
  aws_region          = var.aws_region
  cluster_name        = var.cluster_name
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  vpc_id              = module.networking.vpc_id
  subnet_ids          = module.networking.public_subnets
  depends_on          = [module.iam, module.networking]
}

module "oidc" {
  source                = "./modules/oidc"
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  depends_on           = [module.eks]
}

module "ebs_role" {
  source           = "./modules/ebs-role"
  oidc_provider_arn = module.oidc.oidc_provider_arn
  depends_on       = [module.oidc]
}

module "nodegroup" {
  source           = "./modules/nodegroup"
  cluster_name     = module.eks.eks_cluster_id
  subnet_ids       = module.networking.private_subnets
  node_role_arn    = module.iam.eks_node_role_arn
  vpc_id           = module.networking.vpc_id
  instance_type    = var.instance_type
  desired_capacity = var.desired_capacity
  max_capacity     = var.max_capacity
  min_capacity     = var.min_capacity
  cluster_security_group_id = module.eks.cluster_security_group_id
  depends_on       = [module.eks]
}
