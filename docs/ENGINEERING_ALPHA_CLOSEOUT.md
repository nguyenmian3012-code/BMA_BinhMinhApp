# Engineering Alpha closeout

Updated: 2026-10-03

PR #1 established the original BMA Engineering Alpha foundation. Its useful
work has since been incorporated and superseded by the current `main` branch
through the native-runtime, Bridge, employee-directory, Attendance UI and
resilience pull requests.

## Authoritative architecture

```text
BM Face Terminal
  -> BM Device Bridge (:8789, SQLite outbox/retry)
  -> gateway.redtigerhead.com
  -> BMA Core Windows Service (:8791 staging, :8790 production)
  -> PostgreSQL 17 native
  -> BMA API
  -> BMApp / Admin Web
```

- BMA Core is the only writer to PostgreSQL.
- The Bridge is an edge adapter and durable delivery queue, not a source of
  truth.
- BMApp and Admin Web use BMA API through the Gateway; they do not call the
  Bridge or PostgreSQL directly.
- `binhminh_data_staging` and `binhminh_data` remain isolated.
- Docker is not the authoritative BMA runtime on MinhComp.
- `gateway.redtigerhead.com` is the Binh Minh authority. The older ABMT gateway
  is not a production dependency.

## Work already absorbed by `main`

- Windows Service and native PostgreSQL runtime.
- BM Device Bridge v0.3.2 and canonical `EMPLOYEE_SCAN` ingest.
- Employee directory and the approved 71-person roster workflow.
- BM001 employee-code enforcement.
- Attendance review semantics and mobile resilience tests.
- Native staging verification and Attendance pipeline inspection scripts.

## Remaining gates

- Capture one physical BM001 Entry and Exit pair and verify a single
  Attendance session with `status = Confirmed`.
- Complete offline delivery, retry, idempotency and reconciliation evidence.
- Verify the latest Attendance UI on the Fold 7.
- Keep production deployment and Controlled Pilot at `NO-GO` until these gates
  pass.

## PR #1 reconciliation

The historical production Docker Compose cutover, direct cutover script and
dated session handoff were removed from this PR. Merging this closeout must not
deploy production or change the current Windows-native runtime.
