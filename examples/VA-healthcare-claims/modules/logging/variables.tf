variable "cluster_endpoint"                   { type = string }
variable "cluster_certificate_authority_data" { type = string }
variable "cluster_name"                       { type = string }
variable "oidc_provider_arn"                  { type = string }
variable "logging_namespace"                  { type = string; default = "logging" }
variable "loki_chart_version"                 { type = string; default = "6.6.4" }
variable "fluentbit_version"                  { type = string; default = "0.46.7" }
variable "loki_storage_size"                  { type = string; default = "200Gi" }
variable "log_retention_days"                 { type = number; default = 90 }
variable "s3_log_bucket"                      { type = string }
variable "cloudwatch_log_group"               { type = string; default = "/payments-api/eks" }
