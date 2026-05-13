variable "cluster_endpoint"                   { type = string }
variable "cluster_certificate_authority_data" { type = string }
variable "cluster_name"                       { type = string }
variable "monitoring_namespace"               { type = string; default = "monitoring" }
variable "kube_prometheus_version"            { type = string; default = "61.3.2" }
variable "grafana_admin_password"             { type = string; sensitive = true }
variable "prometheus_retention"               { type = string; default = "30d" }
variable "prometheus_storage_size"            { type = string; default = "100Gi" }
variable "grafana_storage_size"               { type = string; default = "10Gi" }
variable "node_selector"                      { type = map(string); default = {} }

variable "alertmanager_config" {
  type = object({
    slack_webhook_url = string
    slack_channel     = string
    pagerduty_key     = string
  })
}
