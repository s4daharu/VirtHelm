# Definition of Done and Shipping Checklist

No card is done on “works on my machine” alone.

## Per feature
- [ ] PVE versions and endpoint method/parameters/privilege path captured with source date.
- [ ] DTO/domain schema parses nullable fields and rejects malformed types gracefully.
- [ ] UI includes loading, empty, offline, 401/403, errors, retry and stale timestamps.
- [ ] No sensitive data logged, cached unencrypted or in crash summaries.
- [ ] Unit tests and widget tests cover happy, permission, timeout, and negative cases.
- [ ] At least one PVE 9.2 lab integration test; 8.4 regression test for supported features.
- [ ] Android phone accessibility and large font checked.
- [ ] Mutations include explicit confirmation, single-flight execution, UPID follow-up and no automatic retries.
- [ ] Reviewer confirms release build has strict TLS and no debug network trust bypass.
- [ ] Documentation + verification matrix + known limitation updated.

## MVP release gate
- [ ] All P0 features complete and tracked; no unimplemented feature advertised as built.
- [ ] Reproducible toolchain/lockfile; CI format/analyze/test/Android build pass.
- [ ] Real phone verified at minimum and current Android API level.
- [ ] PVE 9.2 primary matrix and 8.4 regression matrix with sanitized evidence.
- [ ] Cross-cluster action isolation, stopped task failure, and timeout-unknown covered.
- [ ] TLS valid/wrong-name/self-signed trust tests plus backup restore checked.
- [ ] App signed, private key off GitHub, no leaks in repository history.
- [ ] Independent/unofficial branding and privacy disclosure reviewed.
- [ ] Console/ticket auth clearly marked deferred unless fully verified.
- [ ] Private GitHub repository visibility confirmed separately.
