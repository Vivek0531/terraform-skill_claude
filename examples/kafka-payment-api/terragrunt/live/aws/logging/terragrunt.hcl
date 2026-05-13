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
  source = "../../../../modules/logging"
}

inputs = {
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  oidc_provider_arn                  = dependency.eks.outputs.oidc_provider_arn

  logging_namespace    = "logging"
  loki_chart_version   = "6.6.4"    # grafana/loki-stack
  fluentbit_version    = "0.46.7"   # fluent/fluent-bit

  loki_storage_size    = "200Gi"
  log_retention_days   = 90

  s3_log_bucket        = "payments-api-logs-${local.account_id}"

  # Ship Kafka consumer-lag and payment audit logs to CloudWatch as well
  cloudwatch_log_group = "/payments-api/eks"
}
