# VectorPlane GCP Integration

<walkthrough-author name="VectorPlane" repositoryUrl="https://github.com/thesystemsguy06/gcp-connect" tutorialName="vectorplane-gcp-onboarding"></walkthrough-author>

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

## Welcome to VectorPlane

**Workload Identity Federation — no service account keys, nothing to rotate.**

This connects your GCP project to VectorPlane. You will need the **pairing code**
shown on your VectorPlane dashboard; it is valid for 20 minutes.

**What gets created:**
- Workload Identity Pool and Provider, restricted to VectorPlane's AWS role
- A service account with read access to Security Command Center findings
- A webhook callback so VectorPlane knows the setup finished

---

## Check your prerequisites

Start here. This changes nothing, and it does not consume your pairing code.

<walkthrough-terminal-command command="./deploy.sh --check">Check prerequisites</walkthrough-terminal-command>

It reports **every** problem it finds at once rather than stopping at the first,
and each one names the command that fixes it. If it reports nothing, continue.

---

## Connect the project

<walkthrough-terminal-command command="./deploy.sh">Connect to VectorPlane</walkthrough-terminal-command>

Paste your pairing code when prompted. The script then works through five steps
and reports each one to your VectorPlane dashboard as it goes, so you can watch
progress here or there.

If a step fails, the error appears in both places along with what to do about
it. You do not need to copy anything back to the dashboard by hand.

**Typical time: 3-5 minutes**, most of it waiting for GCP to enable APIs and
propagate IAM bindings.

---

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**Your GCP project is connected.**

- No service account keys were created or exchanged
- Findings will appear on your VectorPlane dashboard shortly
- To remove the integration at any time: `terraform destroy`

If the dashboard has not updated, run `terraform output` for
`service_account_email` and `external_id` — Integrations > Manual Setup accepts
both directly.

<walkthrough-footnote>
VectorPlane — cloud security remediation
</walkthrough-footnote>
