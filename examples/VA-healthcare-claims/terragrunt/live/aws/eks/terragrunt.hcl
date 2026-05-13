include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../modules/eks"
}

inputs = {
  cluster_name    = "payments-api-eks"
  cluster_version = "1.31"
  vpc_cidr        = "10.0.0.0/16"

  node_groups = {
    payments = {
      instance_types = ["m5.xlarge"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      disk_size      = 50
    }
    kafka = {
      instance_types = ["r5.2xlarge"]
      min_size       = 3
      max_size       = 6
      desired_size   = 3
      disk_size      = 200
      labels         = { workload = "kafka" }
      taints = [{
        key    = "dedicated"
        value  = "kafka"
        effect = "NO_SCHEDULE"
      }]
    }
    monitoring = {
      instance_types = ["m5.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 100
      labels         = { workload = "monitoring" }
    }
  }

  enable_cluster_autoscaler     = true
  enable_aws_load_balancer_controller = true
  enable_ebs_csi_driver         = true
}
