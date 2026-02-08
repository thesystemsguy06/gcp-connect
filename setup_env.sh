#!/bin/bash
  # VectorPlane GCP Onboarding - Environment Setup
  # This script reads variables from cloudshell_context and sets them as environment variables

  set -e

  # Extract context from URL parameter (passed via --context flag)
  if [ -n "$1" ]; then
      CONTEXT="$1"
  else
      # Try to get context from cloudshell metadata
      CONTEXT=$(curl -sf -H "Metadata-Flavor: Google"
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cloudshell_context" 2>/dev/null || echo "")
  fi

  if [ -n "$CONTEXT" ]; then
      echo "Setting up VectorPlane environment variables..."

      # Parse JSON context and extract vectorplane variables
      # Use python3 to safely parse JSON
      python3 << EOF
  import json
  import os
  import sys

  try:
      context = json.loads("""$CONTEXT""")
      vectorplane_vars = context.get('vectorplane', {})

      # Write environment variables to a file that can be sourced
      with open('.env_vectorplane', 'w') as f:
          for key, value in vectorplane_vars.items():
              # Export the variable
              f.write(f'export {key}="{value}"\n')
              print(f"Set {key}")

      print("Environment variables configured successfully!")

  except Exception as e:
      print(f"Warning: Could not parse context: {e}")
      sys.exit(1)
  EOF

      # Source the environment variables
      if [ -f ".env_vectorplane" ]; then
          source .env_vectorplane
          echo "✅ VectorPlane environment variables loaded"

          # Verify required variables are set
          if [ -z "$TF_VAR_external_id" ]; then
              echo "❌ Missing TF_VAR_external_id - onboarding session may have expired"
              exit 1
          fi

          echo "📋 Session ID: $TF_VAR_external_id"
          echo "🔗 Callback URL: $TF_VAR_vectorplane_callback_url"
      else
          echo "❌ Failed to create environment file"
          exit 1
      fi
  else
      echo "❌ No context found - environment variables not available"
      echo "Please make sure you opened Cloud Shell via the VectorPlane onboarding link"
      exit 1
  fi
