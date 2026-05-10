include "root" {
  path = find_in_parent_folders()
}

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    cluster_name                       = "mock-cluster"
  }
}

terraform {
  source = "../../../../modules/monitoring"
}

inputs = {
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data

  monitoring_namespace     = "monitoring"
  kube_prometheus_version  = "61.3.2"  # prometheus-community/kube-prometheus-stack

  grafana_admin_password   = "CHANGE_ME_USE_SSM"

  prometheus_retention     = "30d"
  prometheus_storage_size  = "100Gi"
  grafana_storage_size     = "10Gi"

  alertmanager_config = {
    slack_webhook_url = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
    slack_channel     = "#payments-alerts"
    pagerduty_key     = "YOUR_PAGERDUTY_INTEGRATION_KEY"
  }

  node_selector = { workload = "monitoring" }
}
