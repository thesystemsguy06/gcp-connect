#!/bin/bash
  # VectorPlane GCP Onboarding - Environment Setup
  # This script extracts variables from the Cloud Shell URL and sets them as environment variables

  set -e

  echo "🔧 Setting up VectorPlane environment variables..."

  # The variables are encoded in the URL fragment
  # We'll prompt the user to provide them since we can't access browser URL from shell
  echo ""
  echo "To set up the environment variables, please:"
  echo "1. Look at your browser URL bar"
  echo "2. Find the part after #vectorplane_vars="
  echo "3. Copy that encoded string and paste it below"
  echo ""

  read -p "Paste the encoded variables string: " ENCODED_VARS

  if [ -n "$ENCODED_VARS" ]; then
      echo "Decoding variables..."

      # Decode the base64 encoded JSON
      python3 << EOF
  import json
  import base64
  import sys

  try:
      # Add padding if needed for base64
      encoded = "$ENCODED_VARS"
      padding = len(encoded) % 4
      if padding:
          encoded += '=' * (4 - padding)

      # Decode the JSON
      decoded_json = base64.urlsafe_b64decode(encoded).decode()
      variables = json.loads(decoded_json)

      # Write environment variables to a file
      with open('.env_vectorplane', 'w') as f:
          for key, value in variables.items():
              f.write(f'export {key}="{value}"\n')
              print(f"✓ Set {key}")

      print("\\n✅ Environment variables configured successfully!")

  except Exception as e:
      print(f"❌ Error decoding variables: {e}")
      print("Please make sure you copied the complete string after #vectorplane_vars=")
      sys.exit(1)
  EOF

      # Source the environment variables
      if [ -f ".env_vectorplane" ]; then
          source .env_vectorplane

          # Verify required variables are set
          if [ -z "$TF_VAR_external_id" ]; then
              echo "❌ Missing TF_VAR_external_id - please check the encoded string"
              exit 1
          fi

          echo ""
          echo "📋 Session ID: $TF_VAR_external_id"
          echo "🔗 Callback URL: $TF_VAR_vectorplane_callback_url"
          echo ""
          echo "🎉 Ready to run Terraform!"
          echo ""
          echo "Next steps:"
          echo "  terraform init"
          echo "  terraform apply"
      else
          echo "❌ Failed to create environment file"
          exit 1
      fi
  else
      echo "❌ No variables provided"
      echo "Please make sure you opened Cloud Shell via the VectorPlane onboarding link"
      exit 1
  fi
