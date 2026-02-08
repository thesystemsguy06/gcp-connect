# VectorPlane Auto-Execution Hook
# This file is sourced automatically when bash starts

# Only run once in gcp-connect directory
if [[ "$PWD" =~ gcp-connect && ! -f .vectorplane_initialized ]]; then
    # Wait for repository to be fully cloned and stable
    echo "⏳ Waiting for workspace to be ready..."
    while [ ! -f "setup_env.sh" ] || [ ! -f "main.tf" ]; do
        sleep 1
    done

    # Additional stability check - ensure files are not still being written
    sleep 2

    # Mark as initialized to prevent re-runs
    touch .vectorplane_initialized

    # Clear screen and show menu
    clear

    echo ""
    echo "████████████████████████████████████████████████████████████████"
    echo "🚀 VECTORPLANE GCP ONBOARDING - AUTO-DEPLOYMENT READY"
    echo "████████████████████████████████████████████████████████████████"
    echo ""

    # Verify environment
    if [ -z "$VP_TOKEN" ] || [ -z "$VP_API_BASE" ]; then
        echo "❌ Session configuration missing. Please restart from VectorPlane."
        echo ""
        return
    fi

    echo "✅ Secure session verified"
    echo "✅ Environment: $VP_API_BASE"
    echo ""

    echo "🎯 ONE-CLICK DEPLOYMENT OPTIONS:"
    echo ""
    echo "   [1] FULL AUTO-DEPLOY: Complete integration in one command"
    echo "   [2] GUIDED STEPS: Use tutorial sidebar (click START)"
    echo "   [3] MANUAL: Run commands yourself"
    echo ""

    # Auto-execute with timeout
    echo "⏱️  Auto-starting FULL AUTO-DEPLOY in 10 seconds..."
    echo "    Press any key to choose different option"
    echo ""

    # Read with timeout
    if read -t 10 -n 1 choice; then
        echo ""
        case $choice in
            2)
                echo "📖 Click START in the tutorial sidebar (right panel)"
                echo ""
                ;;
            3)
                echo "⚡ Manual mode: Run './setup_env.sh' when ready"
                echo ""
                ;;
            *)
                choice=1
                ;;
        esac
    else
        # Timeout - auto-deploy
        choice=1
    fi

    if [ "$choice" = "1" ]; then
        echo ""
        echo "🚀 Starting full auto-deployment..."
        echo "════════════════════════════════════════════════════════════════"

        # Execute full deployment
        (
            echo "Step 1/3: Syncing VectorPlane configuration..."
            ./setup_env.sh && \
            echo "" && \
            echo "Step 2/3: Initializing Terraform..." && \
            terraform init && \
            echo "" && \
            echo "Step 3/3: Deploying VectorPlane integration..." && \
            terraform apply -auto-approve && \
            echo "" && \
            echo "🎉 SUCCESS! VectorPlane GCP integration deployed!" && \
            echo "✅ Your GCP project is now connected securely" && \
            echo "✅ Check your VectorPlane dashboard for findings"
        ) || (
            echo "❌ Deployment failed. Check errors above."
        )
    fi
fi
