# Streaming acceptance receipt

## Safety boundary

No SDF mailbox was opened for write, renamed, deleted, or altered. `scanMbox`
keeps one physical line and one range record. `copyLogicalRfcMessage` seeks to
one bounded record and copies it line by line. MIME inspection buffers one
message; it never buffers the complete mailbox.

## Progressive acceptance

| Stage | Input | Result |
| --- | --- | --- |
| 1a | committed synthetic byte-exact mbox fixtures | PASS with ordinary DMD 2.111.0 |
| 1b | 47+ retained CPython `Lib/test/test_email/data/msg_*.txt` fixtures | PASS; each parse retained the complete source range |
| 1c | direct DMD command build of tests and streaming index command | PASS |
| 2 | small real exported mbox sample | PENDING; no export-safe sample was available in this execution environment |
| 3 | bounded SDF byte/message sample | PENDING; this execution environment had no authenticated SDF read path |
| 4 | complete large SDF mailbox | PENDING until stages 2 and 3 pass |

The focused command compiled `model.d`, `mbox.d`, `mime.d`, and
`translated_mailbox_email.d` with `dmd -unittest -Isource`. The resulting
executable reported `1 modules passed unittests`. A separate DMD build produced
the streaming `sdf-mailbox-email` index command.

No GitHub workflow run was attached to the published head during this
verification, so this receipt claims local DMD execution only.
