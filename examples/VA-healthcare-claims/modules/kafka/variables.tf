variable "cluster_endpoint"                   { type = string }
variable "cluster_certificate_authority_data" { type = string }
variable "cluster_name"                       { type = string }
variable "kafka_namespace"                    { type = string; default = "kafka" }
variable "kafka_chart_version"                { type = string; default = "29.3.4" }
variable "storage_class"                      { type = string; default = "gp3" }
variable "storage_size"                       { type = string; default = "100Gi" }

variable "kafka_config" {
  type = object({
    replication_factor  = number
    default_partitions  = number
    min_insync_replicas = number
    retention_hours     = number
    max_message_bytes   = number
  })
  default = {
    replication_factor  = 3
    default_partitions  = 6
    min_insync_replicas = 2
    retention_hours     = 168
    max_message_bytes   = 10485760
  }
}

variable "topics" {
  type = list(object({
    name            = string
    partitions      = number
    replication     = number
    retention_ms    = number
    cleanup_policy  = optional(string, "delete")
  }))
  default = []
}

variable "node_selector" { type = map(string); default = {} }
variable "tolerations"   { type = list(any);   default = [] }

variable "enable_kafka_ui" {
  description = "Deploy Kafka UI (provectus/kafka-ui) for topic and consumer group visibility"
  type        = bool
  default     = true
}

variable "kafka_ui_chart_version" {
  description = "Helm chart version for provectus/kafka-ui"
  type        = string
  default     = "0.7.6"
}
