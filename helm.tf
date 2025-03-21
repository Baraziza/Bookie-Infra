resource "null_resource" "update_kubeconfig" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --alias ${var.cluster_name}"
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
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy = "Delete"
  parameters = {
    type = "gp3"
    encrypted = "true"
  }
  depends_on = [
    helm_release.aws_ebs_csi_driver
  ]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.53.6"
  timeout          = 900
  wait             = true
  atomic           = true


  set {
    name  = "controller.enableStatefulSet"
    value = "false"
  }

  set {
    name  = "configs.secret.argocdServerAdminPassword"
    value = data.aws_secretsmanager_secret_version.argocd_password.secret_string
  }

  set {
    name  = "redis.enabled"
    value = "true"
  }

  set {
    name  = "redis-ha.enabled"
    value = "false"
  }

    set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "nginx"
  }

  set {
    name  = "server.ingress.hosts[0]"
    value = "argocd.baraziza.online"
  }

    set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/ssl-passthrough"
    value = "true"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/backend-protocol"
    value = "HTTPS"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/force-ssl-redirect"
    value = "true"
  }

  set {
    name  = "server.ingress.tls[0].secretName"
    value = "argocd-server-tls"
  }

  set {
    name  = "server.ingress.tls[0].hosts[0]"
    value = "argocd.baraziza.online"
  }

  set {
    name  = "server.ingress.annotations.kubernetes\\.io/ingress\\.class"
    value = "nginx"
  }

  set {
    name  = "server.ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = "letsencrypt-prod"
  }

  values = [
    <<-EOT
    server:
      extraArgs:
        - --insecure
    configs:
      cm:
        url: https://argocd.baraziza.online
        # Enable application auto-creation
        configManagementPlugins: |
          - name: argocd-vault-plugin
        applicationInstanceLabelKey: argocd.argoproj.io/instance

    # Reduce resource requests even further
    controller:
      resources:
        limits:
          cpu: "200m"
          memory: "256Mi"
        requests:
          cpu: "100m"
          memory: "128Mi"
    server:
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
        requests:
          cpu: "50m"
          memory: "64Mi"
    repoServer:
      resources:
        limits:
          cpu: "100m"
          memory: "256Mi"
        requests:
          cpu: "50m"
          memory: "64Mi"
    redis:
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
        requests:
          cpu: "50m"
          memory: "64Mi"
    dex:
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
        requests:
          cpu: "50m"
          memory: "64Mi"
    applicationSet:
      enabled: false
    notifications:
      enabled: false
    server:
      persistentVolume:
        enabled: true
        storageClass: ebs-sc
        size: 5Gi
    EOT
  ]
}

resource "kubernetes_manifest" "bookie_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "bookie-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/Baraziza/Bookie-GitOps"
        targetRevision = "HEAD"
        path           = "k8s-manifests/overlays/dev"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "bookie-app"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
  depends_on = [
    helm_release.argocd,
    module.eks,
    null_resource.update_kubeconfig,
    kubernetes_storage_class.ebs_sc
  ]
}

resource "kubernetes_manifest" "prometheus" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "prometheus"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://prometheus-community.github.io/helm-charts"
        chart          = "prometheus"
        targetRevision = "25.3.0"
        helm = {
          values = <<-EOT
            server:
              persistentVolume:
                enabled: true
                storageClass: ebs-sc
                size: 5Gi
          EOT
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "monitoring"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
  depends_on = [
    helm_release.argocd,
    module.eks,
    null_resource.update_kubeconfig,
    kubernetes_storage_class.ebs_sc
  ]
}

resource "kubernetes_manifest" "grafana" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "grafana"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://grafana.github.io/helm-charts"
        chart          = "grafana"
        targetRevision = "6.58.8"
        helm = {
          values = <<-EOT
            adminPassword: "grafana123"
            persistence:
              enabled: true
              storageClass: ebs-sc
              size: 2Gi
            ingress:
              enabled: true
              ingressClassName: nginx
              annotations:
                cert-manager.io/cluster-issuer: letsencrypt-prod
              hosts:
                - grafana.baraziza.online
              tls:
                - secretName: grafana-tls
                  hosts:
                    - grafana.baraziza.online
          EOT
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "monitoring"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
  depends_on = [
    helm_release.argocd,
    module.eks,
    null_resource.update_kubeconfig,
    kubernetes_storage_class.ebs_sc
  ]
}

resource "null_resource" "delete_pvcs" {
  depends_on = [kubernetes_manifest.grafana, kubernetes_manifest.prometheus]

  triggers = {
    cluster_name = var.cluster_name
    region       = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Delete PVCs in monitoring namespace
      kubectl delete pvc --all -n monitoring || true
      # Wait for PVCs to be deleted
      sleep 10
    EOT

    environment = {
      KUBECONFIG = "~/.kube/config"
    }
  }
}

