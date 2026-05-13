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

# KEDA operator — event-driven autoscaler for Kafka consumer deployments
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_chart_version
  namespace        = var.keda_namespace
  create_namespace = true
  atomic           = true
  timeout          = 300

  values = [
    yamlencode({
      resources = {
        operator = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
        metricServer = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
      prometheus = {
        metricServer = { enabled = true, port = 9022 }
        operator     = { enabled = true, port = 8080 }
      }
    })
  ]
}

# TriggerAuthentication — credentials KEDA uses to query Kafka consumer lag
# For internal bitnami/kafka (no auth): empty secretTargetRef list
# For Confluent Cloud: swap in SASL_SSL secret refs below
resource "kubernetes_manifest" "kafka_trigger_auth" {
  depends_on = [helm_release.keda]

  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = "kafka-trigger-auth"
      namespace = var.consumers_namespace
    }
    spec = {
      # Confluent Cloud: uncomment and populate a Secret with sasl.username/password
      # secretTargetRef = [
      #   { parameter = "sasl", name = "confluent-kafka-secret", key = "sasl" },
      #   { parameter = "tls",  name = "confluent-kafka-secret", key = "tls" },
      # ]
      secretTargetRef = []
    }
  }
}

# ScaledObject: claims-processor scales on claims.submitted consumer lag
resource "kubernetes_manifest" "scaled_object_claims_processor" {
  depends_on = [helm_release.keda]

  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "claims-processor-scaler"
      namespace = var.consumers_namespace
    }
    spec = {
      scaleTargetRef     = { name = "claims-processor" }
      minReplicaCount    = var.scaler_configs.claims_processor.min_replicas
      maxReplicaCount    = var.scaler_configs.claims_processor.max_replicas
      cooldownPeriod     = 60
      triggers = [{
        type = "kafka"
        metadata = {
          bootstrapServers       = var.kafka_bootstrap_servers
          consumerGroup          = "claims-processor-group"
          topic                  = "claims.submitted"
          lagThreshold           = tostring(var.scaler_configs.claims_processor.lag_threshold)
          activationLagThreshold = "10"
          offsetResetPolicy      = "latest"
        }
        authenticationRef = { name = kubernetes_manifest.kafka_trigger_auth.manifest.metadata.name }
      }]
    }
  }
}

# ScaledObject: eligibility-checker scales on claims.eligibility.check lag
resource "kubernetes_manifest" "scaled_object_eligibility_checker" {
  depends_on = [helm_release.keda]

  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "eligibility-checker-scaler"
      namespace = var.consumers_namespace
    }
    spec = {
      scaleTargetRef     = { name = "eligibility-checker" }
      minReplicaCount    = var.scaler_configs.eligibility_checker.min_replicas
      maxReplicaCount    = var.scaler_configs.eligibility_checker.max_replicas
      cooldownPeriod     = 60
      triggers = [{
        type = "kafka"
        metadata = {
          bootstrapServers       = var.kafka_bootstrap_servers
          consumerGroup          = "eligibility-checker-group"
          topic                  = "claims.eligibility.check"
          lagThreshold           = tostring(var.scaler_configs.eligibility_checker.lag_threshold)
          activationLagThreshold = "5"
          offsetResetPolicy      = "latest"
        }
        authenticationRef = { name = kubernetes_manifest.kafka_trigger_auth.manifest.metadata.name }
      }]
    }
  }
}

# ScaledObject: payment-processor scales on claims.payment lag
# Payment SLA is strictest — low threshold (20) scales up immediately
resource "kubernetes_manifest" "scaled_object_payment_processor" {
  depends_on = [helm_release.keda]

  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "payment-processor-scaler"
      namespace = var.consumers_namespace
    }
    spec = {
      scaleTargetRef     = { name = "payment-processor" }
      minReplicaCount    = var.scaler_configs.payment_processor.min_replicas
      maxReplicaCount    = var.scaler_configs.payment_processor.max_replicas
      cooldownPeriod     = 120
      triggers = [{
        type = "kafka"
        metadata = {
          bootstrapServers       = var.kafka_bootstrap_servers
          consumerGroup          = "payment-processor-group"
          topic                  = "claims.payment"
          lagThreshold           = tostring(var.scaler_configs.payment_processor.lag_threshold)
          activationLagThreshold = "5"
          offsetResetPolicy      = "latest"
        }
        authenticationRef = { name = kubernetes_manifest.kafka_trigger_auth.manifest.metadata.name }
      }]
    }
  }
}

# ScaledObject: appeal-tracker scales on claims.appeal lag
resource "kubernetes_manifest" "scaled_object_appeal_tracker" {
  depends_on = [helm_release.keda]

  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "appeal-tracker-scaler"
      namespace = var.consumers_namespace
    }
    spec = {
      scaleTargetRef  = { name = "appeal-tracker" }
      minReplicaCount = 1
      maxReplicaCount = 6
      cooldownPeriod  = 300
      triggers = [{
        type = "kafka"
        metadata = {
          bootstrapServers       = var.kafka_bootstrap_servers
          consumerGroup          = "appeal-tracker-group"
          topic                  = "claims.appeal"
          lagThreshold           = "50"
          activationLagThreshold = "5"
          offsetResetPolicy      = "latest"
        }
        authenticationRef = { name = kubernetes_manifest.kafka_trigger_auth.manifest.metadata.name }
      }]
    }
  }
}
