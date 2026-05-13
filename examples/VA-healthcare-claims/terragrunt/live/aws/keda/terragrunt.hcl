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

dependency "kafka" {
  config_path = "../kafka"
  mock_outputs = {
    bootstrap_servers = "kafka.kafka.svc.cluster.local:9092"
  }
}

terraform {
  source = "../../../../modules/keda"
}

inputs = {
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_name                       = dependency.eks.outputs.cluster_name

  keda_chart_version  = "2.15.1"
  keda_namespace      = "keda"
  consumers_namespace = "va-claims"

  kafka_bootstrap_servers = dependency.kafka.outputs.bootstrap_servers

  scaler_configs = {
    claims_processor = {
      min_replicas  = 2
      max_replicas  = 20
      lag_threshold = 100  # scale when > 100 unprocessed claims per partition
    }
    eligibility_checker = {
      min_replicas  = 2
      max_replicas  = 10
      lag_threshold = 50
    }
    payment_processor = {
      min_replicas  = 2
      max_replicas  = 8
      lag_threshold = 20  # strict payment SLA
    }
  }
}
