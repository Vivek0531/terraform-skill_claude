output "keda_namespace" {
  description = "Namespace where KEDA operator is installed"
  value       = helm_release.keda.namespace
}

output "keda_release_name" {
  description = "Helm release name for KEDA"
  value       = helm_release.keda.name
}

output "scaled_object_names" {
  description = "List of ScaledObject names created for VA claims consumers"
  value = [
    kubernetes_manifest.scaled_object_claims_processor.manifest.metadata.name,
    kubernetes_manifest.scaled_object_eligibility_checker.manifest.metadata.name,
    kubernetes_manifest.scaled_object_payment_processor.manifest.metadata.name,
    kubernetes_manifest.scaled_object_appeal_tracker.manifest.metadata.name,
  ]
}

output "consumers_namespace" {
  description = "Namespace where VA claims consumer deployments are expected"
  value       = var.consumers_namespace
}
