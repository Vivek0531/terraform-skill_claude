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
  kafka_chart_version  = "29.3.4"   # bitnami/kafka — KRaft mode

  kafka_config = {
    replication_factor    = 3
    default_partitions    = 6
    min_insync_replicas   = 2
    retention_hours       = 168      # 7 days default
    max_message_bytes     = 10485760 # 10MB — HL7/FHIR payloads can be large
  }

  enable_kafka_ui        = true
  kafka_ui_chart_version = "0.7.6"

  # VA Healthcare Claims topics
  # HIPAA requires audit trail retention >= 6 years; audit.trail set to 7 years
  topics = [
    # Claim lifecycle
    { name = "claims.submitted",         partitions = 12, replication = 3, retention_ms = 604800000,    cleanup_policy = "delete" },       # 7d
    { name = "claims.eligibility.check", partitions = 12, replication = 3, retention_ms = 604800000,    cleanup_policy = "delete" },       # 7d
    { name = "claims.processing",        partitions = 12, replication = 3, retention_ms = 604800000,    cleanup_policy = "delete" },       # 7d
    { name = "claims.approved",          partitions = 6,  replication = 3, retention_ms = 2592000000,   cleanup_policy = "delete" },       # 30d
    { name = "claims.denied",            partitions = 6,  replication = 3, retention_ms = 2592000000,   cleanup_policy = "delete" },       # 30d
    { name = "claims.appeal",            partitions = 6,  replication = 3, retention_ms = 7776000000,   cleanup_policy = "delete" },       # 90d
    # Payment and notifications
    { name = "claims.payment",           partitions = 6,  replication = 3, retention_ms = 2592000000,   cleanup_policy = "delete" },       # 30d
    { name = "notifications.veteran",    partitions = 6,  replication = 3, retention_ms = 604800000,    cleanup_policy = "delete" },       # 7d
    # Dead-letter and audit
    { name = "claims.dlq",               partitions = 3,  replication = 3, retention_ms = 7776000000,   cleanup_policy = "delete" },       # 90d
    { name = "audit.trail",              partitions = 6,  replication = 3, retention_ms = 220752000000, cleanup_policy = "compact,delete" }, # 7yr HIPAA
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
