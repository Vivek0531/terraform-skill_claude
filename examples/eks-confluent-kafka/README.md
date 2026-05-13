# VA Healthcare Claims — EKS + Confluent Kafka + KEDA CI/CD

Terragrunt-managed infrastructure for the **Veterans Affairs Health Insurance Claims** platform. Apache Kafka (KRaft mode via Helm) event-streams every claim from submission through eligibility, adjudication, payment, and HIPAA-compliant audit archival. KEDA auto-scales consumer deployments on EKS based on real-time Kafka lag.

> **Kafka pattern reference:** [kafka-zero-to-hero](https://github.com/iam-veeramalla/kafka-zero-to-hero) — KRaft mode, topic-per-event-type, consumer group patterns.

---

## The Problem: Veterans' Health Insurance Claims

The US Department of Veterans Affairs processes millions of health insurance claims per year. Before event streaming, the claims pipeline looked like this:

```
Veteran submits claim → batch job (nightly) → eligibility DB query → adjudication worker
→ payment batch (weekly) → notification email (next day)
```

**Real-world failures this caused:**
- Veterans waited weeks for claim decisions that should take hours
- Claims were lost when adjudication workers crashed mid-batch
- A single slow eligibility DB response blocked an entire batch of 50,000 claims
- Appeals had no visibility into current claim state — each system had its own siloed DB
- HIPAA audit logs were scattered across 12 different systems

### How Kafka Solves It

```
Veteran submits claim → claims.submitted topic (immediate, durable)
  → KEDA-scaled eligibility-checker (parallel, stateless)
  → KEDA-scaled claims-processor (adjudication)
  → claims.approved / claims.denied
  → KEDA-scaled payment-processor
  → notifications.veteran (real-time SMS/email)
  → audit.trail (HIPAA 7yr, always-on)
```

Each step is **independent**: a crash in the payment service does not affect eligibility. Claims are never lost. KEDA adds consumer pods within seconds when backlog builds.

---

## Why Move to Confluent Kafka Platform

| Capability | Self-Managed bitnami/kafka | Confluent Platform |
|---|---|---|
| **Schema Registry** | Manual — no enforcement | Built-in; reject malformed HIPAA payloads at produce time |
| **HL7/FHIR Connectors** | Build from scratch | Pre-built Kafka Connect connectors for EHR integration |
| **ksqlDB** | Not available | Real-time SQL on claims stream; power live dashboards |
| **Tiered Storage** | EBS only (expensive at 7yr retention) | Automatic offload to S3 for cold claim records |
| **Multi-Region Replication** | Manual MirrorMaker setup | Cluster Linking — 1-click DR for VA disaster recovery |
| **Control Center** | Kafka UI (topic browse only) | SLA alerting, schema governance, connector management |
| **HIPAA BAA** | No vendor support | Confluent signs HIPAA Business Associate Agreement |
| **Enterprise SLA** | Community support only | 24/7 SLA — required for VA Critical System designation |

**Migration path:** This example runs bitnami/kafka (identical Kafka protocol). Switching to Confluent Cloud requires only changing `bootstrap_servers` and adding a SASL/SSL `TriggerAuthentication` secret in KEDA. Terraform modules are unchanged.

---

## Architecture — VA Claims Message Stream

```mermaid
flowchart TB
    classDef veteran fill:#4A90D9,color:#fff,stroke:#2c6fad
    classDef producer fill:#27AE60,color:#fff,stroke:#1a7a40
    classDef topic fill:#F39C12,color:#fff,stroke:#c07d0a
    classDef consumer fill:#8E44AD,color:#fff,stroke:#6c3483
    classDef keda fill:#E74C3C,color:#fff,stroke:#b03a2e
    classDef infra fill:#2C3E50,color:#fff,stroke:#1a252f
    classDef storage fill:#16A085,color:#fff,stroke:#0e6655

    subgraph external["External"]
        veteran([Veteran / Provider Portal]):::veteran
        va_benefits([VA Benefits Payment System]):::veteran
    end

    subgraph cicd["CI/CD"]
        jenkins([Jenkins\nTerragrunt Deploy\nKafka + KEDA Verify]):::infra
    end

    subgraph eks["AWS EKS — va-claims cluster"]

        subgraph prod_ns["Namespace: va-claims — Producers"]
            claims_api[Claims API]:::producer
        end

        subgraph kafka_ns["Namespace: kafka — 3 Brokers KRaft"]
            t1([claims.submitted\n12p · 7d]):::topic
            t2([claims.eligibility.check\n12p · 7d]):::topic
            t3([claims.processing\n12p · 7d]):::topic
            t4([claims.approved\n6p · 30d]):::topic
            t5([claims.denied\n6p · 30d]):::topic
            t6([claims.appeal\n6p · 90d]):::topic
            t7([claims.payment\n6p · 30d]):::topic
            t8([notifications.veteran\n6p · 7d]):::topic
            t9([claims.dlq\n3p · 90d]):::topic
            t10([audit.trail\n6p · 7yr HIPAA]):::topic
        end

        subgraph keda_ns["Namespace: keda"]
            keda_op[KEDA v2.15\nOperator]:::keda
        end

        subgraph consumers_ns["Namespace: va-claims — KEDA-Scaled Consumers"]
            eligibility[eligibility-checker\n2-10 pods · lag 50]:::consumer
            processor[claims-processor\n2-20 pods · lag 100]:::consumer
            payment[payment-processor\n2-8 pods · lag 20]:::consumer
            notifier[notification-service\n1-6 pods]:::consumer
            appeal[appeal-tracker\n1-6 pods · lag 50]:::consumer
            audit_svc[audit-logger\n2 pods always-on]:::consumer
        end

        subgraph mon_ns["Namespace: monitoring"]
            prometheus[Prometheus]:::infra
            grafana[Grafana]:::infra
            alertmanager[Alertmanager]:::infra
        end

        subgraph log_ns["Namespace: logging"]
            loki[Loki]:::infra
            fluentbit[Fluent Bit DaemonSet]:::infra
        end
    end

    subgraph aws_svc["AWS Services"]
        s3[(S3\nState + Audit Archive)]:::storage
        dynamodb[(DynamoDB\nTF Locks)]:::storage
        cloudwatch[(CloudWatch)]:::storage
    end

    veteran -->|HL7/FHIR claim| claims_api
    claims_api -->|produce| t1
    t1 -->|consume| eligibility
    eligibility -->|eligible| t2
    eligibility -->|ineligible| t5
    t2 -->|consume| processor
    processor -->|approved| t4
    processor -->|denied| t5
    processor -->|exhausted| t9
    t4 -->|consume| payment
    payment -->|disburse| va_benefits
    payment -->|event| t7
    t7 -->|consume| notifier
    t5 -->|consume| notifier
    notifier -->|SMS/email| veteran
    t6 -->|consume| appeal
    appeal -->|re-adjudicate| t2
    t1 & t4 & t5 & t6 & t7 -->|mirror| t10
    t10 -->|consume| audit_svc
    audit_svc -.->|7yr HIPAA archive| s3
    keda_op -.->|lag trigger| t1
    keda_op -.->|scale| processor
    keda_op -.->|lag trigger| t2
    keda_op -.->|scale| eligibility
    keda_op -.->|lag trigger| t7
    keda_op -.->|scale| payment
    keda_op -.->|lag trigger| t6
    keda_op -.->|scale| appeal
    prometheus -->|scrape| kafka_ns
    prometheus -->|scrape| consumers_ns
    grafana -->|query| prometheus
    grafana -->|query| loki
    fluentbit -->|logs| loki
    fluentbit -->|claims logs| cloudwatch
    jenkins -->|terragrunt apply| eks
```

### Claim Lifecycle — Step by Step

| Step | Event | Topic | Consumer | KEDA Scaled? |
|------|-------|-------|----------|:---:|
| 1 | Veteran submits claim | `claims.submitted` | eligibility-checker | ✅ lag > 50 |
| 2 | Eligibility confirmed | `claims.eligibility.check` | claims-processor | ✅ lag > 100 |
| 3 | Adjudication decision | `claims.approved` / `claims.denied` | payment-processor / notifier | ✅ lag > 20 |
| 4 | Payment to VA Benefits | `claims.payment` | notification-service | ✅ |
| 5 | Veteran notified | `notifications.veteran` | — | — |
| 6 | Veteran appeals denial | `claims.appeal` | appeal-tracker | ✅ lag > 50 |
| ∞ | All events mirrored | `audit.trail` | audit-logger | No — always-on |
| ∞ | Failed after retries | `claims.dlq` | ops review | No |

---

## KEDA — Event-Driven Consumer Autoscaling

KEDA replaces static `replicas:` on consumer Deployments with Kafka-lag-based scaling.

```
Lag = 0              → scale to minReplicas  (idle, low cost)
Lag > lagThreshold   → add replicas          (up to maxReplicas)
Lag drops to 0       → cool down, scale back
```

| ScaledObject | Topic | Min | Max | Lag Threshold | Cooldown |
|---|---|:---:|:---:|:---:|:---:|
| `claims-processor-scaler` | `claims.submitted` | 2 | 20 | 100 | 60s |
| `eligibility-checker-scaler` | `claims.eligibility.check` | 2 | 10 | 50 | 60s |
| `payment-processor-scaler` | `claims.payment` | 2 | 8 | 20 | 120s |
| `appeal-tracker-scaler` | `claims.appeal` | 1 | 6 | 50 | 300s |

**Threshold rationale:**
- `claims.payment` threshold = 20 — payment SLA is strictest; scale immediately at first lag
- `claims.appeal` cooldown = 300s — low volume; avoid pod flapping
- `claims.submitted` max = 20 — handles enrollment bursts without pre-provisioning

---

## File Structure

```
examples/eks-confluent-kafka/
├── README.md
├── jenkins/
│   └── Jenkinsfile                      # Pipeline with Kafka + KEDA verify stages
├── scripts/
│   ├── prereqs.sh
│   ├── bootstrap.sh
│   └── verify-kafka.sh
├── modules/
│   ├── eks/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── kafka/
│   │   ├── main.tf                      # StorageClass, NetworkPolicy, bitnami/kafka, Kafka UI
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── keda/
│   │   ├── main.tf                      # KEDA operator + TriggerAuthentication + 4 ScaledObjects
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── monitoring/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── logging/
│       ├── main.tf
│       └── variables.tf
└── terragrunt/
    ├── terragrunt.hcl
    └── live/aws/
        ├── eks/terragrunt.hcl
        ├── kafka/terragrunt.hcl         # VA claims topics (10 topics, HIPAA 7yr audit.trail)
        ├── keda/terragrunt.hcl          # ScaledObjects (depends on eks + kafka)
        ├── monitoring/terragrunt.hcl
        └── logging/terragrunt.hcl
```

---

## Deployment Guide

### Prerequisites

```bash
bash scripts/prereqs.sh
```

### Step 1 — AWS Credentials

```bash
aws configure --profile va-claims
export AWS_PROFILE=va-claims
aws sts get-caller-identity
```

### Step 2 — Bootstrap Remote State

```bash
bash scripts/bootstrap.sh
```

### Step 3 — Deploy EKS

```bash
cd terragrunt/live/aws/eks
terragrunt init && terragrunt plan && terragrunt apply
aws eks update-kubeconfig --name va-claims-eks --region us-east-1
kubectl get nodes
```

### Step 4 — Deploy Kafka

```bash
cd ../kafka
terragrunt init && terragrunt plan && terragrunt apply
bash scripts/verify-kafka.sh
kubectl port-forward -n kafka svc/kafka-ui 8080:80   # http://localhost:8080
```

Expected: 10 VA claims topics created, `audit.trail` retention = 7 years.

### Step 5 — Deploy KEDA

```bash
cd ../keda
terragrunt init && terragrunt plan && terragrunt apply
kubectl get scaledobjects -n va-claims
```

### Step 6 — Deploy Monitoring

```bash
cd ../monitoring && terragrunt init && terragrunt plan && terragrunt apply
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

### Step 7 — Deploy Logging

```bash
cd ../logging && terragrunt init && terragrunt plan && terragrunt apply
```

### Step 8 — Configure Jenkins

1. Jenkins → New Item → Pipeline
2. Script Path: `examples/eks-confluent-kafka/jenkins/Jenkinsfile`
3. Credentials: `aws-role-arn-dev`, `aws-role-arn-staging`, `aws-role-arn-production`, `slack-webhook`
4. Run: **CLOUD=aws, ENVIRONMENT=dev, COMPONENT=all**

Pipeline stages:
```
Validate → Checkout → Setup Tools → Authenticate → Init → Validate Config
→ Plan → [Approval: staging/prod] → Apply
→ Verify Infrastructure
→ Verify Kafka — VA Claims Topics    (6 checks incl. HIPAA retention)
→ Verify KEDA — Consumer Autoscaling (ScaledObjects health)
```

### Step 9 — Deploy All at Once

```bash
cd terragrunt/live/aws
terragrunt run-all apply --terragrunt-non-interactive
# Order: eks → kafka + monitoring + logging (parallel) → keda
```

---

## VA Claims Kafka Topics

| Topic | Partitions | Retention | Cleanup | Purpose |
|-------|:---:|---|---|---|
| `claims.submitted` | 12 | 7 days | delete | Inbound from veteran/provider |
| `claims.eligibility.check` | 12 | 7 days | delete | Eligibility service input |
| `claims.processing` | 12 | 7 days | delete | Adjudication queue |
| `claims.approved` | 6 | 30 days | delete | Approved → payment trigger |
| `claims.denied` | 6 | 30 days | delete | Denial with reason code |
| `claims.appeal` | 6 | 90 days | delete | Veteran appeals |
| `claims.payment` | 6 | 30 days | delete | VA Benefits disbursement |
| `notifications.veteran` | 6 | 7 days | delete | SMS/email to veteran |
| `claims.dlq` | 3 | 90 days | delete | Failed after retries |
| `audit.trail` | 6 | **7 years** | compact,delete | HIPAA §164.312 compliance |

---

## Monitoring & Alerts

| Alert | Threshold | Severity | Destination |
|-------|-----------|----------|-------------|
| `ClaimsProcessorLagHigh` | `claims.submitted` lag > 500 | critical | PagerDuty |
| `PaymentProcessorLagHigh` | `claims.payment` lag > 100 | critical | PagerDuty |
| `EligibilityLagHigh` | `claims.eligibility.check` lag > 200 | warning | Slack |
| `KafkaBrokerDown` | broker unreachable > 1m | critical | PagerDuty |
| `AuditTrailLag` | `audit.trail` consumer lag > 0 for > 5m | critical | PagerDuty + CISO |

---

## Useful Commands

```bash
# Watch KEDA scale in real time
kubectl get hpa -n va-claims -w

# Simulate a burst — 10k test claims, watch claims-processor scale 2→20
kubectl exec -n kafka kafka-broker-0 -- \
  bash -c "seq 1 10000 | kafka-console-producer.sh \
    --bootstrap-server kafka.kafka.svc.cluster.local:9092 \
    --topic claims.submitted"
kubectl get pods -n va-claims -l app=claims-processor -w

# Consumer group lag (all VA claims groups)
kubectl exec -n kafka kafka-broker-0 -- \
  kafka-consumer-groups.sh \
  --bootstrap-server kafka.kafka.svc.cluster.local:9092 \
  --describe --all-groups

# Verify HIPAA 7yr retention
kubectl exec -n kafka kafka-broker-0 -- \
  kafka-topics.sh \
  --bootstrap-server kafka.kafka.svc.cluster.local:9092 \
  --describe --topic audit.trail

# KRaft quorum health
kubectl exec -n kafka kafka-broker-0 -- \
  kafka-metadata-quorum.sh \
  --bootstrap-server kafka.kafka.svc.cluster.local:9092 \
  describe --status

# Kafka UI
kubectl port-forward -n kafka svc/kafka-ui 8080:80

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Tear down
cd terragrunt/live/aws && terragrunt run-all destroy --terragrunt-non-interactive
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Kafka pod `Pending` | Taint mismatch on kafka node group | `kubectl describe pod -n kafka <pod>` → check toleration |
| KEDA `ScaledObject READY=false` | KEDA cannot reach Kafka bootstrap | Check NetworkPolicy allows `keda` namespace on port 9092 |
| Consumer not scaling despite lag | `TriggerAuthentication` wrong | `kubectl describe triggerauthentication -n va-claims` |
| `audit.trail` CI check fails | Retention < 7 years | Re-run kafka `terragrunt apply`; verify `retention_ms=220752000000` |
| `claims.dlq` growing | Consumer crashing after retries | `kubectl logs -n va-claims -l app=claims-processor` |
| KRaft election slow | NTP clock skew > 2s | Sync NTP on worker nodes; restart controller pods |
| EBS volume `Pending` | `kafka-gp3` StorageClass missing | Verify `aws-ebs-csi-driver` addon and `kafka-gp3` SC |
| Confluent migration | Need Schema Registry or HIPAA BAA | Update `kafka_bootstrap_servers`; add SASL/SSL secret in KEDA TriggerAuthentication |
