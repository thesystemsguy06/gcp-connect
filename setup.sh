#!/bin/bash
# Superseded. This script belonged to the VP_TOKEN flow, which no longer exists:
# it read a token from the Cloud Shell URL fragment, and nothing puts one there
# any more. See setup_env.sh for the same note.
echo "setup.sh is superseded. Run ./deploy.sh instead."
echo "You will need the pairing code shown on your VectorPlane dashboard."
echo
echo "  ./deploy.sh --check    check prerequisites only, changes nothing"
echo "  ./deploy.sh            full onboarding"
exit 1
