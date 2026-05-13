terraform {
  required_providers {
    helm       = { source = "hashicorp/helm",       version = "~> 2.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    aws        = { source = "hashicorp/aws",        version = "~> 5.0" }
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

resource "kubernetes_namespace" "logging" {
  metadata {
    name   = var.logging_namespace
    labels = { "app.kubernetes.io/managed-by" = "terragrunt" }
  }
}

# S3 bucket for long-term log archival
resource "aws_s3_bucket" "logs" {
  bucket = var.s3_log_bucket
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration { days = var.log_retention_days }
  }
}

# Loki for log aggregation (Grafana data source)
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version
  namespace  = kubernetes_namespace.logging.metadata[0].name

  timeout         = 300
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      loki = {
        auth_enabled = false
        storage = {
          type = "s3"
          s3 = {
            bucketnames = var.s3_log_bucket
            region      = data.aws_region.current.name
          }
        }
        compactor = {
          retention_enabled       = true
          retention_delete_delay  = "2h"
          retention_delete_worker_count = 150
        }
        limits_config = {
          retention_period = "${var.log_retention_days}d"
        }
      }
      persistence = { enabled = true, size = var.loki_storage_size }
      serviceMonitor = { enabled = true }
    })
  ]
}

# Fluent Bit — ships logs from all pods to Loki + CloudWatch
resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = var.fluentbit_version
  namespace  = kubernetes_namespace.logging.metadata[0].name

  timeout         = 300
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      config = {
        inputs  = "[INPUT]\n    Name tail\n    Path /var/log/containers/*.log\n    multiline.parser docker, cri\n    Tag kube.*\n    Mem_Buf_Limit 50MB\n"
        filters = "[FILTER]\n    Name kubernetes\n    Match kube.*\n    Kube_URL https://kubernetes.default.svc:443\n    Merge_Log On\n    Keep_Log Off\n"
        outputs = <<-EOT
          [OUTPUT]
              Name        loki
              Match       kube.*
              Host        loki.${var.logging_namespace}.svc.cluster.local
              Port        3100
              Labels      job=fluent-bit,cluster=${var.cluster_name}

          [OUTPUT]
              Name        cloudwatch_logs
              Match       kube.*payments*
              region      ${data.aws_region.current.name}
              log_group_name ${var.cloudwatch_log_group}
              log_stream_prefix payments-
              auto_create_group On
        EOT
      }
      serviceMonitor = { enabled = true }
      tolerations = [{ operator = "Exists" }]  # run on all nodes including kafka/monitoring
    })
  ]
}

data "aws_region" "current" {}
