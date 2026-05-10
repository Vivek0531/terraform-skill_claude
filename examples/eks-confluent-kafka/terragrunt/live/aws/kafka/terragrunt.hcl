include "root" {
  path = find_in_parent_folders()
}

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    cluster_name                       = "mock-cluster"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/mock"
  }
}

terraform {
  source = "../../../../modules/kafka"
}

inputs = {
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_name                       = dependency.eks.outputs.cluster_name

  kafka_namespace      = "kafka"
  kafka_chart_version  = "29.3.4"   # bitnami/kafka

  kafka_config = {
    replication_factor    = 3
    default_partitions    = 6
    min_insync_replicas   = 2
    retention_hours       = 168     # 7 days
    max_message_bytes     = 10485760  # 10MB for payment events
  }

  topics = [
    { name = "payments.initiated",  partitions = 12, replication = 3, retention_ms = 604800000 },
    { name = "payments.processing", partitions = 12, replication = 3, retention_ms = 604800000 },
    { name = "payments.completed",  partitions = 12, replication = 3, retention_ms = 2592000000 },  # 30 days
    { name = "payments.failed",     partitions = 6,  replication = 3, retention_ms = 2592000000 },
    { name = "payments.dlq",        partitions = 3,  replication = 3, retention_ms = 7776000000 },  # 90 days
    { name = "audit.events",        partitions = 6,  replication = 3, retention_ms = 31536000000 }, # 1 year
  ]

  storage_class = "gp3"
  storage_size  = "100Gi"

  node_selector = { workload = "kafka" }
  tolerations = [{
    key      = "dedicated"
    value    = "kafka"
    operator = "Equal"
    effect   = "NoSchedule"
  }]
}
