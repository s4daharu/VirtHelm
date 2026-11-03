# Read-only Proxmox REST smoke-test recipes

**Safety:** only read-only GET calls here; use staging credentials, trust the server CA, and never commit secrets, shell history or full debug traces. `PVE_TOKEN_HEADER` must be injected from a secure interactive session or secret store, not hardcoded.

```bash
# Example placeholders only. Replace via a safe secret input mechanism.
export PVE_BASE='https://pve.example.internal:8006/api2/json'
# Do not paste a real token into terminal history or commit a .env file.
read -rsp 'API-token authorization header value: ' PVE_TOKEN_HEADER; echo
# Format entered: PVEAPIToken=operator@pve!android=SECRET
curl --fail-with-body --show-error --silent \
  --header "Authorization: $PVE_TOKEN_HEADER" \
  "$PVE_BASE/version"
curl --fail-with-body --show-error --silent \
  --header "Authorization: $PVE_TOKEN_HEADER" \
  "$PVE_BASE/cluster/resources"
unset PVE_TOKEN_HEADER
```

Avoid `curl -k`/`--insecure`. If your PVE uses a private CA, use `--cacert /trusted/path/cluster-ca.pem` after independently verifying the CA fingerprint; for Android, enroll trust using supported secure mechanisms. Record redacted status/code/schemas for PVE 8.4 and 9.2, and compare against the official API viewer.

**Never** test shutdown/stop/reboot against production machines as a smoke test.
