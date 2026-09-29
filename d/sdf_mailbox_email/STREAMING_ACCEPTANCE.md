# Streaming acceptance receipt

## Safety boundary

No SDF mailbox was opened for write, renamed, deleted, or altered.  The reader
opens a source only for bounded reads.  `scanMbox` retains source offsets and
one physical line at a time; `copyLogicalRfcMessage` seeks to one record and
copies it line by line.

## Progressive acceptance sequence

| Stage | Input | Result |
| --- | --- | --- |
| 1 | committed synthetic fixtures | passed locally with ordinary DMD 2.111.0 (and LDC 1.36 as a compatibility diagnostic); the command produced the checked-in `fixtures/translated-results.md` |
| 2 | small real exported mbox sample | pending user-provided/export-safe sample; no substitution made |
| 3 | bounded SDF byte or message sample | pending explicit SDF read path and bound; source remains read-only |
| 4 | large SDF mailbox | intentionally deferred until stages 1–3 pass |

The local environment did not provide DMD or DUB, so ordinary DMD 2.111.0 was
downloaded from the official D release archive into `/tmp` solely for this
verification.  It compiled both the unit-test executable and the streaming
command, then ran the stage-1 fixtures successfully.  Branch publication is
pending GitHub credentials—the HTTPS remote rejected the push and the connected
GitHub branch-creation call timed out without confirming a remote ref.  This
receipt does not claim remote CI or a large-mailbox acceptance before the
bounded stages exist.
