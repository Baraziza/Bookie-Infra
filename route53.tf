data "aws_route53_zone" "domain" {
  name = "baraziza.online"
}

data "kubernetes_service" "ingress" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}

resource "null_resource" "update_dns" {
  depends_on = [helm_release.ingress_nginx]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for load balancer to be ready
      while ! kubectl get svc -n ingress-nginx ingress-nginx-controller-controller >/dev/null 2>&1; do
        echo "Waiting for ingress controller service..."
        sleep 10
      done
      
      while [ -z "$(kubectl get svc -n ingress-nginx ingress-nginx-controller-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')" ]; do
        echo "Waiting for load balancer hostname..."
        sleep 10
      done
      
      LB_HOSTNAME=$(kubectl get svc -n ingress-nginx ingress-nginx-controller-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
      aws route53 change-resource-record-sets --hosted-zone-id ${data.aws_route53_zone.domain.zone_id} --change-batch '{
        "Changes": [{
          "Action": "UPSERT",
          "ResourceRecordSet": {
            "Name": "dev.baraziza.online.",
            "Type": "CNAME",
            "TTL": 300,
            "ResourceRecords": [{"Value":"'$LB_HOSTNAME'"}]
          }
        }]
      }'
    EOT
  }
} 