================================================================================
  VectorPlane GCP Onboarding
================================================================================

  Run:

      ./deploy.sh

  You will need the pairing code shown on your VectorPlane dashboard. The
  code is valid for 20 minutes; if it expires, start a new connection from
  the dashboard to get a fresh one.

  To check your prerequisites without starting — this changes nothing and
  does not consume a pairing code:

      ./deploy.sh --check

  deploy.sh reports every problem it finds at once, and each one names the
  command that fixes it. Progress appears both here and on your VectorPlane
  dashboard, so you can follow along in either place.

  To remove the integration later:  terraform destroy

================================================================================
