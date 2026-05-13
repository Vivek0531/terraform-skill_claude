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

# gp3 StorageClass tuned for Kafka: high-throughput sequential I/O
resource "kubernetes_storage_class" "kafka_gp3" {
  metadata {
    name = "kafka-gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type       = "gp3"
    iops       = "6000"   # 2x default; keeps up with 3-broker replication writes
    throughput = "250"    # MiB/s -- saturates a single Kafka partition
    encrypted  = "true"
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

# Restrict Kafka traffic: only payment namespace + monitoring may connect on 9092/9093
resource "kubernetes_network_policy" "kafka_ingress" {
  metadata {
    name      = "kafka-ingress"
    namespace  = kubernetes_namespace.kafka.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "kafka" }
    }

    ingress {
      # Allow Kafka-internal broker-to-broker and controller traffic
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.kafka_namespace }
        }
      }
    }

    ingress {
      # Payment API producers / consumers
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "payments" }
        }
      }
      ports {
        port     = "9092"
        protocol = "TCP"
      }
    }

    ingress {
      # Prometheus scrape (JMX exporter on 5556)
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "monitoring" }
        }
      }
      ports {
        port     = "5556"
        protocol = "TCP"
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "helm_release" "kafka" {
  name       = "kafka"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "kafka"
  version    = var.kafka_chart_version
  namespace  = kubernetes_namespace.kafka.metadata[0].name

  timeout         = 600
  cleanup_on_fail = true
  atomic          = true

  values = [
    yamlencode({
      replicaCount = 3

      kraft = {
        enabled = true # KRaft mode -- no ZooKeeper (matches kafka-zero-to-hero pattern)
      }

      controller = {
        replicaCount          = 3
        nodeSelector          = var.node_selector
        tolerations           = var.tolerations
        podAntiAffinityPreset = "hard"
        resources = {
          requests = { cpu = "500m", memory = "2Gi" }
          limits   = { cpu = "2", memory = "4Gi" }
        }
        persistence = {
          enabled      = true
          storageClass = kubernetes_storage_class.kafka_gp3.metadata[0].name
          size         = var.storage_size
        }
      }

      broker = {
        replicaCount          = 3
        nodeSelector          = var.node_selector
        tolerations           = var.tolerations
        podAntiAffinityPreset = "hard"
        resources = {
          requests = { cpu = "1", memory = "4Gi" }
          limits   = { cpu = "4", memory = "8Gi" }
        }
        persistence = {
          enabled      = true
          storageClass = kubernetes_storage_class.kafka_gp3.metadata[0].name
          size         = var.storage_size
        }
        # JVM tuning for payment throughput
        heapOpts = "-Xmx4G -Xms4G -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35"
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
        log.cleaner.enable=true
        unclean.leader.election.enable=false
        replica.lag.time.max.ms=30000
        socket.send.buffer.bytes=102400
        socket.receive.buffer.bytes=102400
        socket.request.max.bytes=104857600
      EOT

      metrics = {
        kafka = { enabled = true }
        jmx   = { enabled = true }
        serviceMonitor = {
          enabled   = true
          namespace = var.kafka_namespace
        }
      }

      # Liveness/readiness tuned for slow KRaft controller elections on first boot
      livenessProbe = {
        initialDelaySeconds = 120
        periodSeconds       = 20
        timeoutSeconds      = 10
        failureThreshold    = 6
      }
      readinessProbe = {
        initialDelaySeconds = 60
        periodSeconds       = 10
        timeoutSeconds      = 5
        failureThreshold    = 6
      }
    })
  ]
}

# Kafka UI -- operational visibility into payment topics and consumer groups
resource "helm_release" "kafka_ui" {
  count = var.enable_kafka_ui ? 1 : 0

  name       = "kafka-ui"
  repository = "https://provectus.github.io/kafka-ui-charts"
  chart      = "kafka-ui"
  version    = var.kafka_ui_chart_version
  namespace  = kubernetes_namespace.kafka.metadata[0].name

  depends_on = [helm_release.kafka]

  values = [
    yamlencode({
      envs = {
        config = {
          KAFKA_CLUSTERS_0_NAME             = "payments-kafka"
          KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS = "kafka.${var.kafka_namespace}.svc.cluster.local:9092"
          KAFKA_CLUSTERS_0_METRICS_PORT     = "5556"
        }
      }

      ingress = {
        enabled = false # expose via kubectl port-forward; no public UI
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }

      nodeSelector = var.node_selector
      tolerations  = var.tolerations
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
    labels    = { "app.kubernetes.io/managed-by" = "terragrunt" }
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
            "--config", "min.insync.replicas=${var.kafka_config.min_insync_replicas}",
            "--config", "compression.type=lz4",
            "--config", "cleanup.policy=${lookup(each.value, "cleanup_policy", "delete")}",
          ]
        }
      }
    }
    backoff_limit = 6
  }

  wait_for_completion = true
  timeouts { create = "5m" }
}
