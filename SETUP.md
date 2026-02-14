# VectorPlane GCP Integration

<walkthrough-author name="VectorPlane" repositoryUrl="https://github.com/vectorplane/gcp-connect" tutorialName="vectorplane-gcp-onboarding"></walkthrough-author>

<walkthrough-tutorial-duration duration="3"></walkthrough-tutorial-duration>

## Welcome to VectorPlane

**Enterprise-grade Workload Identity Federation — zero stored keys.**

This deploys a secure trust relationship between VectorPlane and your GCP project. Everything runs in one step.

**What gets created:**
- Workload Identity Pool & Provider (cross-cloud trust)
- Service Account with least-privilege permissions
- Security Command Center access for finding ingestion
- Automatic webhook callback to VectorPlane

---

## Deploy Integration

Click the button below to deploy. No further input required.

<walkthrough-terminal-command command="bash -c './setup_env.sh && terraform init -input=false && terraform apply -auto-approve -input=false'">🚀 Deploy VectorPlane Integration</walkthrough-terminal-command>

This will:
1. Sync configuration from VectorPlane API
2. Enable required GCP APIs
3. Initialize and apply Terraform

**Estimated time: 2-3 minutes.** Watch the terminal for progress.

---

## ✅ Integration Complete

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**Your GCP project is now connected to VectorPlane securely!**

- Zero service account keys exchanged
- Workload Identity Federation active
- VectorPlane dashboard will show findings shortly
- Run `terraform destroy` to remove anytime

<walkthrough-footnote>
VectorPlane Enterprise Security Platform
</walkthrough-footnote>
