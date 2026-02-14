# =============================================================================
# VectorPlane GCP Onboarding - Webhook Callback
# =============================================================================
# Notifies VectorPlane upon successful Terraform apply.
# Uses HMAC signature for webhook authentication.
# =============================================================================

locals {
  # Build the webhook payload
  # Uses effective_project_id which auto-detects from Cloud Shell if not provided
  webhook_payload = jsonencode({
    external_id                      = var.external_id
    project_number                   = local.project_number
    project_id                       = local.effective_project_id
    organization_id                  = var.onboarding_scope == "ORGANIZATION" ? (var.organization_id != "" ? var.organization_id : var.gcp_scope_id) : null
    folder_id                        = var.onboarding_scope == "FOLDER" ? var.gcp_scope_id : null
    workload_identity_pool_provider  = local.webhook_wif_provider_name
    service_account_email            = google_service_account.vectorplane.email
    onboarding_scope                 = var.onboarding_scope
  })

  # Timestamp for signature freshness
  webhook_timestamp = timestamp()
}

# -----------------------------------------------------------------------------
# Webhook Callback with HMAC Signature
# -----------------------------------------------------------------------------
# This resource executes after all IAM bindings are complete.
# It sends the WIF configuration back to VectorPlane with cryptographic proof.

resource "null_resource" "webhook_callback" {
  # Wait for IAM propagation before calling webhook.
  # time_sleep.iam_propagation transitively depends on all IAM resources
  # and adds a 20-second stabilization window for GCP's control plane.
  depends_on = [
    time_sleep.iam_propagation,
    # Folder-level bindings (not in time_sleep since they're scope-conditional)
    google_folder_iam_member.scc_findings_editor,
    google_folder_iam_member.storage_viewer,
    google_folder_iam_member.folder_viewer,
    google_folder_iam_member.browser,
  ]

  # Re-run if any key values change
  triggers = {
    external_id           = var.external_id
    service_account_email = google_service_account.vectorplane.email
    wif_provider          = local.wif_provider_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    # Shell script to compute HMAC and send webhook
    command = <<-EOT
      set -e

      # Payload to send
      PAYLOAD='${local.webhook_payload}'
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

      # Compute HMAC-SHA256 signature
      # Format: timestamp.payload
      SIGNATURE_INPUT="$TIMESTAMP.$PAYLOAD"
      SIGNATURE=$(echo -n "$SIGNATURE_INPUT" | openssl dgst -sha256 -hmac '${var.webhook_secret}' -binary | base64)

      echo "Sending webhook to VectorPlane..."
      echo "Payload: $PAYLOAD"

      # Send webhook with signature headers
      HTTP_RESPONSE=$(curl -s -w "%%{http_code}" -o /tmp/webhook_response.txt \
        -X POST "${var.vectorplane_callback_url}" \
        -H "Content-Type: application/json" \
        -H "X-VectorPlane-Signature: sha256=$SIGNATURE" \
        -H "X-VectorPlane-Timestamp: $TIMESTAMP" \
        -H "X-VectorPlane-External-ID: ${var.external_id}" \
        -d "$PAYLOAD" \
        --connect-timeout 30 \
        --max-time 60)

      RESPONSE_BODY=$(cat /tmp/webhook_response.txt 2>/dev/null || echo "")

      echo "HTTP Status: $HTTP_RESPONSE"
      echo "Response: $RESPONSE_BODY"

      # Check for success (2xx status code)
      if [[ "$HTTP_RESPONSE" =~ ^2[0-9][0-9]$ ]]; then
        echo "Webhook callback succeeded!"
        exit 0
      else
        echo "ERROR: Webhook callback failed with status $HTTP_RESPONSE"
        echo "Please verify your VectorPlane session is still active."
        exit 1
      fi
    EOT

    environment = {
      # Prevent sensitive values from appearing in logs
      TF_LOG = ""
    }
  }
}

# -----------------------------------------------------------------------------
# Verification Resource (Optional Manual Check)
# -----------------------------------------------------------------------------
# If the webhook fails, users can manually verify the setup worked.

resource "null_resource" "verification_instructions" {
  depends_on = [null_resource.webhook_callback]

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "=============================================="
      echo "VectorPlane GCP Integration - Setup Complete!"
      echo "=============================================="
      echo ""
      echo "If the automatic callback failed, provide these"
      echo "details to VectorPlane support:"
      echo ""
      echo "  External ID:           ${var.external_id}"
      echo "  Project ID:            ${local.effective_project_id}"
      echo "  Service Account:       ${google_service_account.vectorplane.email}"
      echo "  WIF Provider:          ${local.wif_provider_name}"
      echo "  Scope:                 ${var.onboarding_scope}"
      echo ""
      echo "=============================================="
    EOT
  }
}
