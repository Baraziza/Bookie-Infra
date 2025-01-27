provider "helm" {
  kubernetes {
    host                   = module.eks.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.eks_cluster_certificate_authority)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

resource "null_resource" "update_kubeconfig" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region}"
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.13.1"

  set {
    name  = "installCRDs"
    value = "true"
  }

  values = [
    <<-EOT
    clusterIssuers:
      - name: letsencrypt-prod
        spec:
          acme:
            server: https://acme-v02.api.letsencrypt.org/directory
            email: baraziza17@gmail.com
            privateKeySecretRef:
              name: letsencrypt-prod
            solvers:
              - http01:
                  ingress:
                    class: nginx
    EOT
  ]

  # Wait for CRDs to be ready
  set {
    name  = "webhook.timeoutSeconds"
    value = "30"
  }

  set {
    name  = "webhook.enabled"
    value = "true"
  }

  depends_on = [module.eks, null_resource.update_kubeconfig]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx-controller"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.7.1"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  wait = true
  timeout = 300

  depends_on = [module.eks, null_resource.update_kubeconfig]
}

resource "null_resource" "delete_load_balancer" {
  depends_on = [helm_release.ingress_nginx]

  triggers = {
    cluster_endpoint = module.eks.eks_cluster_endpoint
    cluster_name     = var.cluster_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete service -n ingress-nginx ingress-nginx-controller || true
      sleep 30
    EOT

    environment = {
      KUBECONFIG = "~/.kube/config"
    }
  }
}

resource "helm_release" "aws_ebs_csi_driver" {
  name             = "aws-ebs-csi-driver"
  namespace        = "kube-system"
  repository       = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart            = "aws-ebs-csi-driver"
  version          = "2.25.0"

  values = [
    <<-EOT
    controller:
      serviceAccount:
        create: true
        name: ebs-csi-controller-sa
        annotations:
          eks.amazonaws.com/role-arn: ${module.oidc.ebs_csi_driver_trust_role_arn}
          eks.amazonaws.com/audience: "sts.amazonaws.com"
          eks.amazonaws.com/token-expiration: "86400"
      extraVolumeTags:
        Environment: dev
        Terraform: "true"
    EOT
  ]

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_sc" {
  metadata {
    name = "ebs-sc"
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  depends_on = [
    helm_release.aws_ebs_csi_driver
  ]
}

resource "helm_release" "bookie" {
  name             = "bookie"
  namespace        = "bookie-app"
  create_namespace = true
  force_update     = true
  recreate_pods    = true
  chart            = "./helm-charts/bookie/bookie"
  timeout          = 600
  wait             = true

  values = [
    <<-EOT
    mysql:
      storage:
        storageClass: ebs-sc
        size: 10Gi
    ingress:
      host: dev.baraziza.online
    EOT
  ]

  depends_on = [
    helm_release.cert_manager,
    helm_release.ingress_nginx,
    kubernetes_storage_class.ebs_sc,
    helm_release.aws_ebs_csi_driver
  ]
}