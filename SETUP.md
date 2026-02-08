# VectorPlane GCP Onboarding

<walkthrough-author name="VectorPlane" repositoryUrl="https://github.com/vectorplane/gcp-connect" tutorialName="gcp-onboarding"></walkthrough-author>

<walkthrough-watcher-constant key="VP_TOKEN" value="{{VP_TOKEN}}"></walkthrough-watcher-constant>

## Welcome to VectorPlane GCP Integration!

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

This setup creates secure access to your GCP project using Workload Identity Federation (WIF).

**Security highlights:**
- ✅ No secrets exchanged - VectorPlane never stores GCP keys
- ✅ Short-lived tokens - 15-minute setup sessions
- ✅ Enterprise-grade sync - Bearer token authentication
- ✅ Customer-controlled - Revoke access anytime

Click **Start** below to begin the guided setup.

## Step 1: Sync Configuration

<walkthrough-spotlight-pointer cssSelector="#terminal">Click here to focus the terminal</walkthrough-spotlight-pointer>

Your VectorPlane session is ready! Click the button below to sync your configuration automatically.

<walkthrough-terminal-command command="./setup_env.sh">Sync VectorPlane Configuration</walkthrough-terminal-command>

This command will:
- Authenticate with VectorPlane using your bearer token
- Pull configuration via secure API endpoint
- Generate `terraform.tfvars.json` for Terraform auto-loading
- Validate session with enterprise-grade error messages

**Expected output:** You should see "✅ Configuration synced successfully" when complete.

## Step 2: Initialize Terraform

Now initialize Terraform with the synced configuration:

<walkthrough-terminal-command command="terraform init">Initialize Terraform</walkthrough-terminal-command>

This downloads the required Google Cloud provider and prepares your workspace.

## Step 3: Review Deployment Plan

Review what resources will be created:

<walkthrough-terminal-command command="terraform plan">Review Terraform Plan</walkthrough-terminal-command>

This shows you:
- **Workload Identity Pool** - Trust boundary for external providers
- **WIF Provider** - Trusts VectorPlane's AWS account (101460827772)
- **Service Account** - Identity for VectorPlane to access your resources
- **IAM Bindings** - Security Command Center and asset discovery permissions

## Step 4: Deploy Resources

Deploy the VectorPlane integration:

<walkthrough-terminal-command command="terraform apply">Deploy VectorPlane Integration</walkthrough-terminal-command>

**Important:** Type `yes` when prompted to confirm the deployment.

This will:
1. Create the GCP resources
2. Send a secure webhook to VectorPlane
3. Complete the integration automatically

## 🎉 Success!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Your GCP project is now connected to VectorPlane!

**What happens next:**
- VectorPlane can now scan your GCP resources securely
- You'll see findings appear in your VectorPlane dashboard
- The integration uses Workload Identity Federation (no stored keys)

**To remove the integration:** Run `terraform destroy` anytime.

**Need help?** Contact VectorPlane support with your session ID.

<walkthrough-footnote>
Powered by VectorPlane Enterprise Security Platform
</walkthrough-footnote>
