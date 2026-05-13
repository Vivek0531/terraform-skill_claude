variable "cluster_endpoint"                   { type = string }
variable "cluster_certificate_authority_data" { type = string }
variable "cluster_name"                       { type = string }

variable "keda_namespace" {
  description = "Namespace for the KEDA operator"
  type        = string
  default     = "keda"
}

variable "keda_chart_version" {
  description = "Helm chart version for kedacore/keda"
  type        = string
  default     = "2.15.1"
}

variable "consumers_namespace" {
  description = "Namespace where VA claims consumer Deployments live"
  type        = string
  default     = "va-claims"
}

variable "kafka_bootstrap_servers" {
  description = "Kafka bootstrap server for KEDA Kafka triggers"
  type        = string
  default     = "kafka.kafka.svc.cluster.local:9092"
}

variable "scaler_configs" {
  description = "Per-consumer KEDA ScaledObject configuration"
  type = object({
    claims_processor = object({
      min_replicas  = number
      max_replicas  = number
      lag_threshold = number
    })
    eligibility_checker = object({
      min_replicas  = number
      max_replicas  = number
      lag_threshold = number
    })
    payment_processor = object({
      min_replicas  = number
      max_replicas  = number
      lag_threshold = number
    })
  })
  default = {
    claims_processor = {
      min_replicas  = 2
      max_replicas  = 20
      lag_threshold = 100
    }
    eligibility_checker = {
      min_replicas  = 2
      max_replicas  = 10
      lag_threshold = 50
    }
    payment_processor = {
      min_replicas  = 2
      max_replicas  = 8
      lag_threshold = 20
    }
  }
}
