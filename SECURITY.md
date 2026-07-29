# Security policy

## Supported versions

Security fixes are applied to the latest release on the `main` branch.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use the
repository's **Security** tab to submit a private vulnerability report to the
OpsRabbit maintainers. Include the affected version, impact, reproduction
steps, and any suggested mitigation.

Do not include real API keys, SSH keys, cloud credentials, customer data, or
other secrets in the report. Replace them with clearly marked placeholders.

## Deployment responsibility

This project configures model-serving software on an existing machine. The
operator remains responsible for host patching, NVIDIA driver lifecycle,
network firewall rules, TLS termination, secret distribution, access logging,
monitoring, backups, and compliance requirements.
