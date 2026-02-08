# VectorPlane GCP Integration

<walkthrough-author name="VectorPlane" repositoryUrl="https://github.com/vectorplane/gcp-connect" tutorialName="vectorplane-gcp-onboarding"></walkthrough-author>

<walkthrough-tutorial-duration duration="3"></walkthrough-tutorial-duration>

## 🚀 Deploy VectorPlane GCP Integration

**System Architect Design: Action-First, Zero-Friction UX**

Your secure session is ready. Complete the integration with guided one-click deployment.

**Security Model:**
- 🔐 Workload Identity Federation (no stored keys)
- ⏱️ 15-minute secure session window
- 🎯 Zero-trust AWS-to-GCP authentication

---

## Step 1: Sync Your Secure Identity

<walkthrough-spotlight-pointer cssSelector="#terminal" text="Your terminal is ready for deployment">
</walkthrough-spotlight-pointer>

Click the button below to authenticate and sync your configuration:

<walkthrough-terminal-command command="./setup_env.sh">🔐 Sync VectorPlane Configuration</walkthrough-terminal-command>

**What this does:**
- Authenticates with VectorPlane using your bearer token
- Pulls secure configuration via API
- Generates `terraform.tfvars.json` automatically
- Validates session integrity

**Expected output:** "✅ Configuration synced successfully"

---

## Step 2: Initialize Terraform

<walkthrough-terminal-command command="terraform init">📦 Initialize Terraform</walkthrough-terminal-command>

Downloads the Google Cloud provider and initializes your workspace.

---

## Step 3: Deploy Integration

<walkthrough-spotlight-pointer cssSelector="#terminal" text="Deploy with confidence - all variables are pre-configured">
</walkthrough-spotlight-pointer>

<walkthrough-terminal-command command="terraform apply -auto-approve">🚀 Deploy VectorPlane Integration</walkthrough-terminal-command>

**What gets created:**
- **Workload Identity Pool** - Trust boundary for VectorPlane
- **Service Account** - Secure identity for resource access
- **IAM Bindings** - Security Command Center permissions
- **Webhook Notification** - Automatic completion signal

---

## 🎉 Integration Complete!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**Your GCP project is now connected to VectorPlane securely.**

✅ **Zero keys exchanged** - Uses Workload Identity Federation
✅ **Automatic discovery** - VectorPlane will scan your resources
✅ **Dashboard ready** - Findings will appear in VectorPlane
✅ **Customer controlled** - Run `terraform destroy` anytime

<walkthrough-footnote>
**Need help?** Contact VectorPlane support with your session ID
</walkthrough-footnote>
