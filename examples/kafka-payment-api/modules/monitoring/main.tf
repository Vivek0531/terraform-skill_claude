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

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name   = var.monitoring_namespace
    labels = { "app.kubernetes.io/managed-by" = "terragrunt" }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout         = 600
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      grafana = {
        adminPassword = var.grafana_admin_password
        persistence   = { enabled = true, size = var.grafana_storage_size }
        nodeSelector  = var.node_selector
        sidecar = {
          dashboards = { enabled = true, searchNamespace = "ALL" }
        }
        additionalDataSources = [{
          name      = "Loki"
          type      = "loki"
          url       = "http://loki.logging.svc.cluster.local:3100"
          access    = "proxy"
          isDefault = false
        }]
      }

      prometheus = {
        prometheusSpec = {
          retention             = var.prometheus_retention
          nodeSelector          = var.node_selector
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources        = { requests = { storage = var.prometheus_storage_size } }
              }
            }
          }
          # Scrape Kafka JMX metrics from ServiceMonitor
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false
        }
      }

      alertmanager = {
        config = {
          global = { resolve_timeout = "5m" }
          route = {
            group_by        = ["alertname", "cluster", "service"]
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "12h"
            receiver        = "slack"
            routes = [{
              match    = { severity = "critical" }
              receiver = "pagerduty"
            }]
          }
          receivers = [
            {
              name = "slack"
              slack_configs = [{
                api_url  = var.alertmanager_config.slack_webhook_url
                channel  = var.alertmanager_config.slack_channel
                title    = "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}"
                text     = "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"
              }]
            },
            {
              name = "pagerduty"
              pagerduty_configs = [{
                routing_key = var.alertmanager_config.pagerduty_key
              }]
            }
          ]
        }
      }
    })
  ]
}

# Kafka-specific alerting rules
resource "kubernetes_manifest" "kafka_alerts" {
  depends_on = [helm_release.kube_prometheus_stack]

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "kafka-alerts"
      namespace = var.monitoring_namespace
      labels    = { "release" = "kube-prometheus-stack" }
    }
    spec = {
      groups = [{
        name = "kafka.rules"
        rules = [
          {
            alert = "KafkaConsumerLagHigh"
            expr  = "kafka_consumergroup_lag > 10000"
            for   = "5m"
            labels    = { severity = "warning" }
            annotations = {
              summary     = "Kafka consumer lag high on {{ $labels.consumergroup }}"
              description = "Consumer group {{ $labels.consumergroup }} lag is {{ $value }} on topic {{ $labels.topic }}"
            }
          },
          {
            alert = "KafkaBrokerDown"
            expr  = "up{job='kafka'} == 0"
            for   = "1m"
            labels    = { severity = "critical" }
            annotations = {
              summary     = "Kafka broker {{ $labels.instance }} is down"
              description = "Kafka broker has been down for more than 1 minute"
            }
          },
          {
            alert = "PaymentProcessingDelayed"
            expr  = "kafka_consumergroup_lag{topic=~'payments.*'} > 5000"
            for   = "3m"
            labels    = { severity = "critical" }
            annotations = {
              summary     = "Payment processing is delayed"
              description = "Payment topic {{ $labels.topic }} consumer lag is {{ $value }}"
            }
          }
        ]
      }]
    }
  }
}
