# Contributing

Contributions are welcome through pull requests. Direct changes to `main` are
not accepted after the repository's initial commit.

Before opening a pull request:

1. Keep the installer cloud-neutral unless the project scope explicitly changes.
2. Do not add credentials, API keys, private addresses, or customer information.
3. Pin model revisions to full commit hashes. Runtime defaults deliberately follow official `latest`
   tags, so explain and test any runtime-image policy change.
4. Run `./scripts/validate.sh` locally.
5. Update the README when supported hardware, behavior, or security changes.

Changes that install drivers, format disks, open firewalls, or provision cloud
resources require a separate design discussion and explicit approval.
