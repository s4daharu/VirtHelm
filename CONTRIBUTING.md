# Contributing and Review Standards

Keep the repository private until the owner chooses otherwise. Proposed work must cite official PVE API viewer/docs and test against target versions, include error/security/accessibility cases, and update the verification matrix. Work in small branches and pull requests. Do not commit token secrets, PVE private CA keys, signing keystores, `.env`, device logs or actual infrastructure inventories. Use `python3 scripts/check_docs.py` before PR. Flutter source lives under `app/` after bootstrap; only Android platform runner is supported.
