# Intentionally does nothing.
#
# This held the superseded VP_TOKEN flow: it printed a menu, waited 10 seconds,
# and on timeout ran `terraform apply -auto-approve` by itself. Bash does not
# source a .bashrc from a repository directory, so it was inert where it sits —
# but it is written to be copied to $HOME, and there it would auto-deploy.
#
# Onboarding is `./deploy.sh`, run deliberately, by a person holding a pairing
# code from the VectorPlane dashboard. Nothing here should run on its own.
