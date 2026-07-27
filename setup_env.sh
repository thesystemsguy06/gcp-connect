#!/bin/bash
# Superseded. This script belonged to the VP_TOKEN flow, which no longer exists:
# VP_TOKEN is not issued by any current code path, so this could only ever fail
# with a confusing "token not found".
#
# It is kept as a pointer because older documentation and bookmarked tutorials
# still name it. Everything it used to do — pulling configuration, aligning the
# project, enabling APIs — now happens inside deploy.sh, after a preflight that
# checks your prerequisites before anything is changed.
echo "setup_env.sh is superseded. Run ./deploy.sh instead."
echo "You will need the pairing code shown on your VectorPlane dashboard."
echo
echo "  ./deploy.sh --check    check prerequisites only, changes nothing"
echo "  ./deploy.sh            full onboarding"
exit 1
