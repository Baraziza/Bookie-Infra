data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ebs_csi_driver" {
  name = "AmazonEKS_EBS_CSI_DriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_arn, "arn:aws:iam::[0-9]+:oidc-provider/", "")}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
          "${replace(var.oidc_provider_arn, "arn:aws:iam::[0-9]+:oidc-provider/", "")}:aud": "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

output "role_arn" {
  value = aws_iam_role.ebs_csi_driver.arn
} 