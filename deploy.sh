#!/bin/bash
# VectorPlane GCP Integration — Device Flow Onboarding (RFC 8628)
# Exchanges a pairing code for the full Terraform configuration,
# then deploys Workload Identity Federation via Terraform.
#
# Idempotent: safe to re-run after partial failures.
#   - Terraform state is stored in a GCS bucket (survives Cloud Shell restarts)
#   - Pre-flight recovery handles soft-deleted and orphaned GCP resources
#   - Every failure reports clean error details to the VectorPlane dashboard

set -e

# Production default; override with VP_API_BASE for dev/testing
API_BASE="${VP_API_BASE:-https://api.vectorplane.io}"
EXCHANGE_URL="${API_BASE}/api/v1/onboarding/gcp/pairing-exchange"
ERROR_URL="${API_BASE}/api/v1/onboarding/gcp/report-error"
PROGRESS_URL="${API_BASE}/api/v1/onboarding/gcp/report-progress"
HEARTBEAT_URL="${API_BASE}/api/v1/onboarding/gcp/heartbeat"

# Session ID — set after successful pairing exchange
SESSION_ID=""

# ── Helpers ───────────────────────────────────────────────────────────

# Strip ANSI escape codes and Terraform box-drawing characters.
# Terraform wraps errors in ANSI color codes and Unicode box chars
# that are unreadable in a web dashboard.
clean_tf_output() {
    sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r│' | sed 's/^[[:space:]]*//'
}

# Send error telemetry to VectorPlane dashboard.
# Uses jq for safe JSON encoding (handles quotes, newlines, special chars).
report_error() {
    local error_type="${1:-unexpected}"
    local detail="${2:-}"
    if [ -n "$SESSION_ID" ]; then
        local payload
        payload=$(jq -n \
            --arg sid "$SESSION_ID" \
            --arg etype "$error_type" \
            --arg det "$detail" \
            '{session_id: $sid, error_type: $etype, detail: $det}')
        curl -s -X POST "$ERROR_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            > /dev/null 2>&1 || true
    fi
}

# ── G4: one reporting channel for progress AND failure ────────────────
#
# Progress and failure travel the same path on purpose. Built separately they are two
# routes that can disagree about the same step — "stuck at 4" and "failed at 4" would
# arrive differently. As one, the ABSENCE of a completion is itself the signal, and the
# dashboard stops saying "Waiting for GCP handshake" to describe every possible state.
#
# Best-effort throughout: a reporting failure must never fail a deployment that is working.
TOTAL_STEPS=5
CURRENT_STEP=0
CURRENT_STEP_NAME=""

report_progress() {
    local step="$1" name="$2" state="$3" detail="${4:-}"
    CURRENT_STEP="$step"
    CURRENT_STEP_NAME="$name"
    [ -n "$SESSION_ID" ] || return 0
    local payload
    payload=$(jq -n \
        --arg sid "$SESSION_ID" --argjson step "$step" --argjson total "$TOTAL_STEPS" \
        --arg name "$name" --arg state "$state" --arg det "$detail" \
        '{session_id:$sid, step:$step, total_steps:$total, name:$name, state:$state, detail:$det}')
    curl -s -X POST "$PROGRESS_URL" \
        -H "Content-Type: application/json" -d "$payload" > /dev/null 2>&1 || true
}

# ── G6-2: heartbeat, so "dead" and "slow" stop looking identical ──────
#
# Without this, a user who closes the Cloud Shell tab mid-Terraform and a Terraform run
# that is simply taking a while produce the SAME observation: a session in PROVISIONING
# with no new step. Long steps are exactly when someone is most likely to walk away, so the
# gap between step reports is precisely where the ambiguity lives.
#
# Runs in the background and is killed on exit — including on failure, so a dead script
# stops pinging promptly rather than looking alive for another interval.
HEARTBEAT_PID=""

start_heartbeat() {
    [ -n "$SESSION_ID" ] || return 0
    (
        while true; do
            sleep 30
            curl -s -X POST "$HEARTBEAT_URL" \
                -H "Content-Type: application/json" \
                -d "{\"session_id\": \"$SESSION_ID\"}" > /dev/null 2>&1 || true
        done
    ) &
    HEARTBEAT_PID=$!
}

stop_heartbeat() {
    [ -n "$HEARTBEAT_PID" ] && kill "$HEARTBEAT_PID" 2>/dev/null || true
}
trap stop_heartbeat EXIT

step_start() { report_progress "$1" "$2" "started"; }
step_ok()    { report_progress "$CURRENT_STEP" "$CURRENT_STEP_NAME" "succeeded" "${1:-}"; }

# Catch what nobody listed. The Terraform-not-installed failure produced a permanent
# spinner precisely because it was not an anticipated failure mode, so no report_error
# call covered it. A trap covers the set nobody thought of — which is the set that matters.
on_unexpected_error() {
    local code=$?
    report_progress "$CURRENT_STEP" "${CURRENT_STEP_NAME:-startup}" "failed" \
        "unexpected failure (exit $code) at line $LINENO: $BASH_COMMAND"
    report_error "unexpected" "line $LINENO: $BASH_COMMAND (exit $code)"
}
trap on_unexpected_error ERR

# ── G2: preflight — everything at once, before anything is changed ────
#
# The failure this removes: a user with three missing prerequisites used to learn about them
# across three separate round trips, each costing a Cloud Shell session and a pairing code,
# because checks were interleaved with mutations. Requirement 4 was only discoverable after
# satisfying 1-3.
#
# Rules, all three load-bearing:
#   * nothing is mutated until every check passes
#   * EVERY failure is listed, not just the first
#   * each failure carries the command that fixes it — a message the reader cannot act on
#     is a status update, not an error
#
# `./deploy.sh --check` runs the environment half standalone, consuming no pairing code, so
# it can be re-run as often as needed while fixing things.
PREFLIGHT_FAILURES=0
PREFLIGHT_JSON=""

_check_pass() {
    printf '  \033[32m✓\033[0m %-22s %s\n' "$1" "$2"
    PREFLIGHT_JSON="${PREFLIGHT_JSON}$(jq -nc --arg n "$1" --arg d "$2" \
        '{name:$n, ok:true, detail:$d, remedy:null}'),"
}

_check_fail() {
    # $1 label, $2 what was found, $3.. remedy lines
    local label="$1" detail="$2"; shift 2
    printf '  \033[31m✗\033[0m %-22s %s\n' "$label" "$detail"
    local remedy=""
    for line in "$@"; do
        printf '    %s\n' "$line"
        remedy="${remedy}${line}"$'\n'
    done
    PREFLIGHT_FAILURES=$((PREFLIGHT_FAILURES + 1))
    PREFLIGHT_JSON="${PREFLIGHT_JSON}$(jq -nc --arg n "$label" --arg d "$detail" --arg r "$remedy" \
        '{name:$n, ok:false, detail:$d, remedy:$r}'),"
}

# Environment checks — no project context needed, so `--check` can run them alone.
preflight_environment() {
    if command -v terraform > /dev/null 2>&1; then
        _check_pass "terraform" "$(terraform version 2>/dev/null | head -1)"
    else
        # Google removed Terraform from the default Cloud Shell image. Install to $HOME:
        # Cloud Shell only persists $HOME, so a system install evaporates with the VM.
        _check_fail "terraform" "not installed" \
            "Cloud Shell no longer ships Terraform. Install it to your home directory:" \
            "  mkdir -p ~/bin && curl -fsSL https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip -o /tmp/tf.zip" \
            "  unzip -o /tmp/tf.zip -d ~/bin && export PATH=\"\$HOME/bin:\$PATH\""
    fi

    command -v jq > /dev/null 2>&1 \
        && _check_pass "jq" "present" \
        || _check_fail "jq" "not installed" "  sudo apt-get install -y jq"

    local account
    account=$(gcloud config get-value account 2>/dev/null || echo "")
    if [ -n "$account" ] && [ "$account" != "(unset)" ]; then
        _check_pass "gcloud account" "$account"
    else
        _check_fail "gcloud account" "not authenticated" \
            "  gcloud auth login"
    fi

    # R5: a wrong working directory used to masquerade as "invalid pairing code".
    # cloudshell_open clones into a subdirectory, and a re-login under a different Google
    # account lands in a different home entirely.
    if [ -f "./main.tf" ] && [ -f "./variables.tf" ]; then
        _check_pass "working directory" "$(pwd)"
    else
        _check_fail "working directory" "$(pwd) — no main.tf here" \
            "The onboarding module is not in this directory. It is usually at:" \
            "  cd ~/cloudshell_open/gcp-connect   # or wherever you cloned it" \
            "  ls main.tf variables.tf            # both must be present"
    fi

    if curl -fsS --max-time 10 "${API_BASE}/health" > /dev/null 2>&1; then
        _check_pass "VectorPlane API" "$API_BASE"
    else
        _check_fail "VectorPlane API" "$API_BASE is not reachable" \
            "Check the URL, or that your tunnel is running if this is a dev backend."
    fi
}

# Project checks — need the pairing exchange to have told us which project and scope.
preflight_project() {
    local project="$1" scope="$2" account="$3"

    # G7 + R4: gcloud conflates "project not found" with "permission denied", and they need
    # opposite user actions — choose a different project, versus get access to this one.
    # We know the identifier, so we can tell them apart before deploying.
    local describe_err
    if describe_err=$(gcloud projects describe "$project" --format="value(projectId)" 2>&1); then
        _check_pass "project access" "$project"
    elif echo "$describe_err" | grep -qi "not found\|does not exist"; then
        _check_fail "project access" "$project does not exist" \
            "Check the project ID — note this is the ID, not the number:" \
            "  gcloud projects list" \
            "Then re-run onboarding in VectorPlane with the correct ID."
        return
    else
        _check_fail "project access" "$project exists but $account cannot see it" \
            "This account is not a member of the project, or lacks resourcemanager.projects.get." \
            "If the project is in an Organization, check you are signed in as an org user:" \
            "  gcloud auth list"
        return
    fi

    # Ask GCP which permissions this caller actually holds, rather than guessing a role.
    # "You may need Owner or Editor" existed because the script could not tell. It can.
    local needed missing granted
    needed='["serviceusage.services.enable","iam.workloadIdentityPools.create","iam.serviceAccounts.create","resourcemanager.projects.setIamPolicy","storage.buckets.create"]'
    # testIamPermissions is REST-only — there is no `gcloud projects test-iam-permissions`
    # subcommand. Calling one silently failed on every run, and because the failure was
    # discarded the empty result read as "holds none of them": every user was told to grant
    # five permissions they already had. Call the API directly.
    local response err
    response=$(curl -sS -X POST \
        "https://cloudresourcemanager.googleapis.com/v1/projects/${project}:testIamPermissions" \
        -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" \
        -H "Content-Type: application/json" \
        -d "{\"permissions\":${needed}}" 2>&1)

    # A check that could not run is NOT a check that found nothing. Collapsing the two is
    # what produced the bug above, so "unverifiable" gets its own branch and says why.
    err=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [ -n "$err" ] || ! echo "$response" | jq -e 'has("permissions")' >/dev/null 2>&1; then
        _check_fail "permissions" "could not verify: ${err:-no response from Cloud Resource Manager}" \
            "VectorPlane could not read your permissions, so it will not guess at them." \
            "If the API is not enabled on this project, enable it and re-run:" \
            "  gcloud services enable cloudresourcemanager.googleapis.com --project=$project"
        return
    fi

    granted=$(echo "$response" | jq -r '.permissions[]? // empty')
    missing=""
    for perm in $(echo "$needed" | jq -r '.[]'); do
        echo "$granted" | grep -qx "$perm" || missing="${missing}${perm} "
    done

    if [ -z "$missing" ]; then
        _check_pass "permissions" "all required permissions present"
    else
        # Whether the user can fix this themselves turns on ONE of the missing
        # permissions. Granting a role is itself an IAM write, so if
        # setIamPolicy is what they are missing, handing them
        # `add-iam-policy-binding` gives them a command that fails with the same
        # error they are already looking at — a remedy that cannot be applied is
        # worse than none, because it costs a round trip to discover.
        if echo "$missing" | grep -q "resourcemanager.projects.setIamPolicy"; then
            _check_fail "permissions" "missing: ${missing}" \
                "You cannot grant these to yourself: setIamPolicy is among the" \
                "missing permissions, so any add-iam-policy-binding you run will" \
                "fail the same way. Someone else has to grant it." \
                "" \
                "Ask a project Owner, or an Organization Administrator, to run:" \
                "  gcloud projects add-iam-policy-binding $project \\" \
                "    --member=user:$account --role=roles/owner" \
                "" \
                "If you ARE the Cloud Identity super admin and this still fails:" \
                "super admin is not a GCP IAM role and grants no project access." \
                "Grant yourself roles/resourcemanager.organizationAdmin at the" \
                "organization level in the console (IAM & Admin > IAM, select the" \
                "organization, not the project), then re-run."
        else
            _check_fail "permissions" "missing: ${missing}" \
                "Grant the missing permissions. The simplest grant that covers them:" \
                "  gcloud projects add-iam-policy-binding $project \\" \
                "    --member=user:$account --role=roles/owner"
        fi
        if [ "$scope" = "ORGANIZATION" ]; then
            _check_fail "org permissions" "ORGANIZATION scope needs org-level IAM admin" \
                "Project Owner does NOT confer this. At the organization level you need:" \
                "  roles/resourcemanager.organizationAdmin" \
                "Or re-run onboarding with PROJECT scope instead."
        fi
    fi
}

# G6-4: report VectorPlane resources this project ALREADY has, before touching anything.
#
# Two ways a project ends up half-onboarded: a run whose session expired mid-Terraform (VP
# forgets, GCP remembers), and a partial apply that then failed. Either way a retry meets a
# name the FIRST run created — and WIF pool ids are unique per project, so it collides on
# something the user cannot interpret.
#
# The script already recovers by importing those resources into state, which is
# non-destructive and the right default. What was missing is saying so. A user whose project
# is silently adopted has had their infrastructure taken under management without being
# told, and the standing rule is that VectorPlane does not change a customer's
# infrastructure without confirmation.
preflight_existing_resources() {
    local project="$1" pool_id="$2"
    local imported="" reused=""

    # Split by what actually happens to each, because the two are different
    # mechanisms and only one of them is "adoption". Saying ADOPT about the state
    # bucket would be the exact defect this preflight exists to prevent: the
    # bucket is not a Terraform resource at all — no google_storage_bucket exists
    # in any .tf — so it can never be imported into state. It is the GCS *backend*
    # that holds the state, created by gcloud in step 3.
    gcloud iam workload-identity-pools describe "$pool_id" \
        --location=global --project="$project" > /dev/null 2>&1 \
        && imported="${imported}WIF pool '$pool_id', "

    gcloud iam service-accounts describe \
        "vectorplane-security@${project}.iam.gserviceaccount.com" \
        --project="$project" > /dev/null 2>&1 \
        && imported="${imported}service account 'vectorplane-security', "

    gcloud storage buckets describe "gs://${project}-vectorplane-tf-state" \
        --project="$project" > /dev/null 2>&1 \
        && reused="state bucket gs://${project}-vectorplane-tf-state"

    if [ -z "$imported" ] && [ -z "$reused" ]; then
        _check_pass "existing resources" "none — this is a fresh setup"
        return
    fi

    local detail="${imported%, }"
    [ -n "$reused" ] && detail="${detail:+${detail}; }${reused}"

    # Not a failure: both outcomes are correct and non-destructive. But they are
    # material facts about the user's project and they should read them first.
    printf '  \033[33m!\033[0m %-22s %s\n' "existing resources" "$detail"

    if [ -n "$imported" ]; then
        printf '    From an earlier VectorPlane setup attempt: %s\n' "${imported%, }"
        printf '    This run will ADOPT these — import them into Terraform state and\n'
        printf '    manage them from here. They are not duplicated and not deleted.\n'
    fi

    if [ -n "$reused" ]; then
        printf '    Your Terraform state bucket already exists. It is reused, not\n'
        printf '    imported — it holds the state rather than being described by it,\n'
        printf '    so any previous state is preserved. This is the normal case on a\n'
        printf '    re-run and needs nothing from you.\n'
    fi

    if [ -n "$imported" ]; then
        # Only offer to delete what was actually found. Printing both unconditionally told
        # users to delete resources that do not exist, which reads as "the check saw
        # something I cannot see" and sends them investigating a non-problem.
        printf '    To start fresh instead, delete them before re-running:\n'
        case "$imported" in *"WIF pool"*)
            printf '      gcloud iam workload-identity-pools delete %s --location=global --project=%s\n' \
                "$pool_id" "$project" ;;
        esac
        case "$imported" in *"service account"*)
            printf '      gcloud iam service-accounts delete vectorplane-security@%s.iam.gserviceaccount.com\n' \
                "$project" ;;
        esac
    fi

    PREFLIGHT_JSON="${PREFLIGHT_JSON}$(jq -nc \
        --arg i "${imported%, }" --arg r "$reused" \
        '{name:"existing resources", ok:true,
          detail:([(if $i == "" then empty else "will adopt: " + $i end),
                   (if $r == "" then empty else "will reuse: " + $r end)] | join("; ")),
          remedy:"Both are non-destructive. To start fresh, delete the adopted resources before re-running."}'),"
}

preflight_report() {
    local checks="[${PREFLIGHT_JSON%,}]"
    [ -n "$SESSION_ID" ] || return 0
    # G3: the terminal is not the only audience. Without this the dashboard keeps saying
    # "Waiting for GCP handshake" while the user reads a clear report in Cloud Shell — and
    # a colleague watching the dashboard learns nothing.
    local state="succeeded"; [ "$PREFLIGHT_FAILURES" -gt 0 ] && state="failed"
    curl -s -X POST "$PROGRESS_URL" -H "Content-Type: application/json" -d "$(jq -nc \
        --arg sid "$SESSION_ID" --arg state "$state" --argjson checks "$checks" \
        --argjson n "$PREFLIGHT_FAILURES" \
        '{session_id:$sid, step:0, total_steps:5, name:"Checking prerequisites",
          state:$state, detail:(if $n>0 then "\($n) prerequisite(s) missing" else "all checks passed" end),
          checks:$checks}')" > /dev/null 2>&1 || true
}

preflight_finish() {
    echo ""
    if [ "$PREFLIGHT_FAILURES" -gt 0 ]; then
        echo "$PREFLIGHT_FAILURES problem(s) found. Nothing has been changed."
        echo "Fix the above and re-run. To re-check without using a pairing code:"
        echo "  ./deploy.sh --check"
        preflight_report
        exit 1
    fi
    preflight_report
}

# `--check`: environment half only, no pairing code consumed.
if [ "${1:-}" = "--check" ]; then
    echo ""
    echo "VectorPlane onboarding — checking prerequisites"
    echo ""
    preflight_environment
    echo ""
    if [ "$PREFLIGHT_FAILURES" -gt 0 ]; then
        echo "$PREFLIGHT_FAILURES problem(s) found. Nothing has been changed."
        exit 1
    fi
    echo "Environment looks good. Run ./deploy.sh to continue."
    echo "(Project access and permissions are checked once you enter a pairing code.)"
    exit 0
fi

echo ""
echo "------------------------------------------------"
echo "  VectorPlane GCP Onboarding"
echo "------------------------------------------------"
echo ""

# ── Step 1: Pairing Code (with retry) ────────────────────────────────
MAX_CODE_ATTEMPTS=3
ATTEMPT=0
BODY=""

while [ $ATTEMPT -lt $MAX_CODE_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    read -p "Enter pairing code from dashboard (e.g. VP-XXXX): " USER_CODE
    USER_CODE=$(echo "$USER_CODE" | tr '[:lower:]' '[:upper:]' | xargs)

    if [ -z "$USER_CODE" ]; then
        echo "No code entered."
        if [ $ATTEMPT -lt $MAX_CODE_ATTEMPTS ]; then
            echo ""
            continue
        fi
        echo "Max attempts reached. Get a fresh code from your VectorPlane dashboard."
        exit 1
    fi

    echo ""
    echo "[1/5] Authenticating with VectorPlane..."

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$EXCHANGE_URL" \
        -H "Content-Type: application/json" \
        -d "{\"pairing_code\": \"$USER_CODE\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        break
    fi

    ERROR_MSG=$(echo "$BODY" | jq -r '.detail // "Unknown error"' 2>/dev/null || echo "$BODY")
    echo "Error: $ERROR_MSG"

    if [ "$HTTP_CODE" = "410" ]; then
        echo ""
        echo "A newer code was generated. Check your VectorPlane dashboard."
        echo ""
    elif [ $ATTEMPT -lt $MAX_CODE_ATTEMPTS ]; then
        echo ""
        echo "Try again, or get a new code from your VectorPlane dashboard."
        echo ""
    else
        echo ""
        echo "Max attempts reached. Please regenerate a code in the dashboard."
        exit 1
    fi
done

# Write the full payload as terraform.tfvars.json
echo "$BODY" > terraform.tfvars.json

# Validate JSON
if ! jq empty terraform.tfvars.json 2>/dev/null; then
    echo "Error: VectorPlane returned a configuration this script cannot use."
    echo "       This is a problem on our side — nothing was changed in your project."
    echo "       Contact support with pairing code $USER_CODE."
    exit 1
fi

# Extract session ID for error reporting
SESSION_ID=$(jq -r '.external_id' terraform.tfvars.json)
PROJECT_ID=$(jq -r '.project_id' terraform.tfvars.json)
ONBOARDING_SCOPE=$(jq -r '.onboarding_scope // "PROJECT"' terraform.tfvars.json)
GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "your-account")
echo "Identity verified. Project: $PROJECT_ID"
step_start 1 "Authenticated with VectorPlane"
step_ok "project $PROJECT_ID"
start_heartbeat

# ── Preflight — after the exchange (a read), before anything is changed ──
#
# The exchange has to come first: it is what tells us WHICH project and scope to check. It
# mutates nothing, so "nothing changed before preflight passes" still holds.
echo ""
echo "Checking prerequisites..."
echo ""
preflight_environment
preflight_project "$PROJECT_ID" "$ONBOARDING_SCOPE" "$GCLOUD_ACCOUNT"
preflight_existing_resources "$PROJECT_ID" "$(jq -r '.wif_pool_id' terraform.tfvars.json)"
preflight_finish

# ── From here on, errors are reported to the dashboard ────────────────

# ── Step 2: Align GCP project + enable APIs ───────────────────────────
echo ""
echo "[2/5] Preparing GCP project..."
step_start 2 "Preparing GCP project"

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    gcloud config set project "$PROJECT_ID" --quiet
fi

if ! gcloud services enable \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    sts.googleapis.com \
    iamcredentials.googleapis.com \
    securitycenter.googleapis.com \
    storage.googleapis.com \
    --quiet 2>&1; then
    report_error "api_enable" "Could not enable required GCP APIs on $PROJECT_ID"
    echo "Error: could not enable the required GCP APIs on $PROJECT_ID."
    echo "       This account ($GCLOUD_ACCOUNT) needs roles/serviceusage.serviceUsageAdmin"
    echo "       on the project. Grant it with:"
    echo "         gcloud projects add-iam-policy-binding $PROJECT_ID \\"
    echo "           --member=user:$GCLOUD_ACCOUNT --role=roles/serviceusage.serviceUsageAdmin"
    if [ "$ONBOARDING_SCOPE" = "ORGANIZATION" ]; then
        echo ""
        echo "       Organization scope also needs roles/resourcemanager.organizationAdmin"
        echo "       at the ORG level. Project Owner does not include it."
    fi
    exit 1
fi
echo "GCP APIs enabled."
step_ok "APIs enabled"

# ── Step 3: Set up remote state backend (GCS) ────────────────────────
# Terraform state is stored in GCS so retries after partial failures
# "just work" — Cloud Shell sessions are ephemeral but GCS persists.
echo ""
echo "[3/5] Configuring state backend..."
step_start 3 "Configuring state backend"

STATE_BUCKET="${PROJECT_ID}-vectorplane-tf-state"

# Create bucket if it doesn't exist (idempotent)
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" --project="$PROJECT_ID" > /dev/null 2>&1; then
    if ! gcloud storage buckets create "gs://${STATE_BUCKET}" \
        --project="$PROJECT_ID" \
        --location=us \
        --uniform-bucket-level-access \
        --quiet 2>&1; then
        report_error "state_bucket" "Failed to create Terraform state bucket"
        echo "Error: could not create the Terraform state bucket in $PROJECT_ID."
        echo "       This account ($GCLOUD_ACCOUNT) needs roles/storage.admin. Grant it with:"
        echo "         gcloud projects add-iam-policy-binding $PROJECT_ID \\"
        echo "           --member=user:$GCLOUD_ACCOUNT --role=roles/storage.admin"
        exit 1
    fi
    echo "  Created state bucket: ${STATE_BUCKET}"
else
    echo "  Using existing state bucket: ${STATE_BUCKET}"
fi

# Generate backend config for Terraform
cat > backend.tf <<BACKEND_EOF
terraform {
  backend "gcs" {
    bucket = "${STATE_BUCKET}"
    prefix = "vectorplane/gcp-onboarding"
  }
}
BACKEND_EOF

# ── Step 4: Terraform init + pre-flight recovery ─────────────────────
echo ""
echo "[4/5] Initializing Terraform..."
step_start 4 "Initialising Terraform"
if ! terraform init -input=false -reconfigure 2>&1; then
    report_error "terraform_init" "terraform init failed"
    echo "Error: terraform init failed. Usually the state bucket is unreachable or"
    echo "       credentials have expired. Check:"
    echo "         gcloud auth list                       # is the expected account active?"
    echo "         gsutil ls gs://${STATE_BUCKET}         # can this account see the bucket?"
    exit 1
fi

# --- Pre-flight resource recovery ---
# Handles two edge cases that would otherwise cause 409 conflicts:
#   (a) Resources exist in GCP but not in Terraform state (orphaned from
#       a previous session that used a different state backend)
#   (b) Resources were soft-deleted (GCP retains for 30 days) — must be
#       undeleted before Terraform can manage them again
#
# If state already has resources (normal retry), this block is skipped entirely.

RESOURCES=$(terraform state list 2>/dev/null || echo "")
if [ -z "$RESOURCES" ]; then
    echo "  Reconciling with existing GCP resources..."

    # Read resource IDs from tfvars
    WIF_POOL_ID=$(jq -r '.wif_pool_id' terraform.tfvars.json)
    WIF_PROVIDER_ID=$(jq -r '.wif_provider_id' terraform.tfvars.json)
    DEV_OIDC_URL=$(jq -r '.dev_oidc_issuer_url // ""' terraform.tfvars.json)
    SA_ID="vectorplane-security"
    SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
    POOL_PATH="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"

    # Phase 1: Undelete soft-deleted resources (idempotent — fails silently
    # if the resource is already active or was never created)
    if gcloud iam workload-identity-pools undelete "$WIF_POOL_ID" \
        --location=global --project="$PROJECT_ID" --quiet > /dev/null 2>&1; then
        echo "    Restored soft-deleted WIF pool"
        sleep 3  # Wait for pool restoration to propagate
    fi

    if gcloud iam workload-identity-pools providers undelete "$WIF_PROVIDER_ID" \
        --workload-identity-pool="$WIF_POOL_ID" \
        --location=global --project="$PROJECT_ID" --quiet > /dev/null 2>&1; then
        echo "    Restored soft-deleted AWS provider"
    fi

    if [ -n "$DEV_OIDC_URL" ]; then
        if gcloud iam workload-identity-pools providers undelete "vectorplane-dev-oidc" \
            --workload-identity-pool="$WIF_POOL_ID" \
            --location=global --project="$PROJECT_ID" --quiet > /dev/null 2>&1; then
            echo "    Restored soft-deleted OIDC provider"
        fi
    fi

    # Phase 2: Import existing resources into Terraform state.
    # Each import succeeds if the resource exists in GCP, fails silently if not.
    # This lets terraform apply update/no-op existing resources instead of
    # trying to create them (which would 409).
    IMPORTED=0

    if terraform import -input=false \
        "google_iam_workload_identity_pool.vectorplane" \
        "$POOL_PATH" > /dev/null 2>&1; then
        echo "    Imported WIF pool"
        IMPORTED=$((IMPORTED + 1))
    fi

    if terraform import -input=false \
        "google_iam_workload_identity_pool_provider.aws" \
        "${POOL_PATH}/providers/${WIF_PROVIDER_ID}" > /dev/null 2>&1; then
        echo "    Imported AWS provider"
        IMPORTED=$((IMPORTED + 1))
    fi

    if [ -n "$DEV_OIDC_URL" ]; then
        if terraform import -input=false \
            'google_iam_workload_identity_pool_provider.dev_oidc[0]' \
            "${POOL_PATH}/providers/vectorplane-dev-oidc" > /dev/null 2>&1; then
            echo "    Imported OIDC provider"
            IMPORTED=$((IMPORTED + 1))
        fi
    fi

    if terraform import -input=false \
        "google_service_account.vectorplane" \
        "projects/${PROJECT_ID}/serviceAccounts/${SA_EMAIL}" > /dev/null 2>&1; then
        echo "    Imported service account"
        IMPORTED=$((IMPORTED + 1))
    fi

    if [ $IMPORTED -gt 0 ]; then
        echo "  Recovered $IMPORTED existing resource(s) into state."
    else
        echo "  No existing resources found. Fresh deployment."
    fi
else
    echo "  State loaded ($(echo "$RESOURCES" | wc -l | tr -d ' ') resources). Resuming."
fi

# ── Step 5: Terraform apply ───────────────────────────────────────────
echo ""
echo "[5/5] Deploying integration..."
step_start 5 "Deploying integration"
TF_OUTPUT=""
if TF_OUTPUT=$(terraform apply -auto-approve -input=false 2>&1); then
    echo "$TF_OUTPUT"
    step_ok "integration deployed"
    echo ""
    echo "================================================"
    echo "  VectorPlane GCP integration deployed!"
    echo ""
    echo "  - Workload Identity Federation active"
    echo "  - Zero service account keys exchanged"
    echo "  - Check your VectorPlane dashboard for findings"
    echo ""
    echo "  To remove: terraform destroy"
    echo "================================================"
else
    echo "$TF_OUTPUT"
    # Extract clean error lines for dashboard (strip ANSI codes + box chars)
    LAST_ERROR=$(echo "$TF_OUTPUT" | clean_tf_output | grep -i "error" | tail -3 | head -c 500)
    report_error "terraform_apply" "$LAST_ERROR"
    echo ""
    # G7: this used to say "Your VectorPlane dashboard will show details." The dashboard
    # said "Waiting for GCP handshake" — forever. It took a user standing in front of the
    # real Terraform error and sent them to a spinner that knew nothing, while the answer
    # scrolled past in the terminal behind them. A promise the product does not keep is
    # worse than silence. Point at the output that actually has the answer.
    #
    # Once the G4 reporting channel lands, the dashboard can answer and this can say so.
    echo "Error: deployment failed. The Terraform output above shows why."
    echo "       Nothing was left half-applied; re-run ./deploy.sh once fixed."
    exit 1
fi
