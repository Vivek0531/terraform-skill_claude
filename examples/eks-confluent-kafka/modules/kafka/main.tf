terraform {
  required_providers {
    helm       = { source = "hashicorp/helm",       version = "~> 2.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
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

resource "kubernetes_namespace" "kafka" {
  metadata {
    name = var.kafka_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terragrunt"
      "monitoring"                   = "prometheus"
    }
  }
}

resource "helm_release" "kafka" {
  name       = "kafka"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "kafka"
  version    = var.kafka_chart_version
  namespace  = kubernetes_namespace.kafka.metadata[0].name

  timeout          = 600
  cleanup_on_fail  = true
  atomic           = true

  values = [
    yamlencode({
      replicaCount = 3

      kraft = {
        enabled = true  # KRaft mode — no ZooKeeper (matches kafka-zero-to-hero pattern)
      }

      controller = {
        replicaCount   = 3
        nodeSelector   = var.node_selector
        tolerations    = var.tolerations
        podAntiAffinityPreset = "hard"
        resources = {
          requests = { cpu = "500m", memory = "2Gi" }
          limits   = { cpu = "2",    memory = "4Gi" }
        }
      }

      broker = {
        replicaCount   = 3
        nodeSelector   = var.node_selector
        tolerations    = var.tolerations
        podAntiAffinityPreset = "hard"
        resources = {
          requests = { cpu = "1",    memory = "4Gi" }
          limits   = { cpu = "4",    memory = "8Gi" }
        }
      }

      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.storage_size
      }

      extraConfig = <<-EOT
        default.replication.factor=${var.kafka_config.replication_factor}
        num.partitions=${var.kafka_config.default_partitions}
        min.insync.replicas=${var.kafka_config.min_insync_replicas}
        log.retention.hours=${var.kafka_config.retention_hours}
        message.max.bytes=${var.kafka_config.max_message_bytes}
        auto.create.topics.enable=false
        delete.topic.enable=true
        compression.type=lz4
        log.segment.bytes=536870912
      EOT

      metrics = {
        kafka = { enabled = true }
        jmx   = { enabled = true }
        serviceMonitor = {
          enabled   = true
          namespace = var.kafka_namespace
        }
      }
    })
  ]
}

# Create payment topics after Kafka is ready
resource "kubernetes_job" "create_topics" {
  depends_on = [helm_release.kafka]

  for_each = { for t in var.topics : t.name => t }

  metadata {
    name      = "create-topic-${replace(each.key, ".", "-")}"
    namespace = var.kafka_namespace
  }

  spec {
    template {
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "kafka-admin"
          image = "bitnami/kafka:3.8.0"
          command = [
            "kafka-topics.sh",
            "--bootstrap-server", "kafka.${var.kafka_namespace}.svc.cluster.local:9092",
            "--create", "--if-not-exists",
            "--topic", each.value.name,
            "--partitions", tostring(each.value.partitions),
            "--replication-factor", tostring(each.value.replication),
            "--config", "retention.ms=${each.value.retention_ms}",
          ]
        }
      }
    }
    backoff_limit = 6
  }

  wait_for_completion = true
  timeouts { create = "5m" }
}
