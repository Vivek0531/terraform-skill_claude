output "bootstrap_servers" {
  description = "Kafka bootstrap server address (cluster-internal)"
  value       = "kafka.${var.kafka_namespace}.svc.cluster.local:9092"
}

output "kafka_namespace" {
  description = "Kubernetes namespace where Kafka is deployed"
  value       = kubernetes_namespace.kafka.metadata[0].name
}

output "kafka_release_name" {
  description = "Helm release name for Kafka"
  value       = helm_release.kafka.name
}

output "kafka_ui_enabled" {
  description = "Whether Kafka UI is deployed"
  value       = var.enable_kafka_ui
}

output "topic_names" {
  description = "List of Kafka topic names created"
  value       = [for t in var.topics : t.name]
}

output "storage_class_name" {
  description = "StorageClass used for Kafka broker PVCs"
  value       = kubernetes_storage_class.kafka_gp3.metadata[0].name
}
