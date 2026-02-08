# VectorPlane GCP Integration

<walkthrough-author name="VectorPlane" repositoryUrl="https://github.com/vectorplane/gcp-connect" tutorialName="vectorplane-gcp-onboarding"></walkthrough-author>

<walkthrough-tutorial-duration duration="3"></walkthrough-tutorial-duration>

## 🚀 Secure GCP Integration Deployment

**Enterprise-grade Workload Identity Federation setup with zero stored keys.**

Your secure session is ready. Choose your preferred deployment method:

**Option A:** Use the terminal auto-deployment (already running)
**Option B:** Follow guided steps below

---

## Step 1: Sync VectorPlane Configuration

<walkthrough-spotlight-pointer cssSelector="#terminal" text="Terminal shows auto-deployment options">
</walkthrough-spotlight-pointer>

Authenticate and retrieve your secure configuration:

<walkthrough-terminal-command command="./setup_env.sh">🔐 Sync Configuration</walkthrough-terminal-command>

**What happens:**
- Bearer token authentication with VectorPlane API
- Secure configuration pull via HTTPS
- Automatic `terraform.tfvars.json` generation
- Session validation and error handling

---

## Step 2: Initialize Terraform Workspace

<walkthrough-terminal-command command="terraform init">📦 Initialize Terraform</walkthrough-terminal-command>

Downloads Google Cloud provider and prepares deployment workspace.

---

## Step 3: Deploy Secure Integration

<walkthrough-terminal-command command="terraform apply">🚀 Deploy Integration</walkthrough-terminal-command>

**Creates:**
- **Workload Identity Pool** - External identity trust boundary
- **Service Account** - VectorPlane's GCP access identity
- **IAM Bindings** - Security Center scanning permissions
- **Webhook Callback** - Automatic completion notification

**Type `yes` when prompted to confirm deployment.**

---

## ✅ Integration Complete

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**Your GCP project is now connected to VectorPlane securely!**

- Zero service account keys exchanged
- Workload Identity Federation active
- VectorPlane dashboard will show findings
- Run `terraform destroy` to remove anytime

<walkthrough-footnote>
VectorPlane Enterprise Security Platform
</walkthrough-footnote>
