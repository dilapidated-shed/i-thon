# Feature-parity record

This table covers the retained read-only SDF mailbox/message path identified in
`PROVENANCE.md`.

| Retained behavior | D implementation | Evidence |
| --- | --- | --- |
| Incremental mailbox scan | `scanMbox` holds one physical line and one record | large input size does not determine scan memory |
| CPython mbox `From ` rule | every physical line beginning `From ` starts a record | adversarial fixture produces three records |
| bytes before first separator | ignored as CPython does | translated test |
| blank separator line handling | one LF-only empty line before a boundary/EOF is excluded | translated test |
| mboxrd and mboxo logical bytes | one protective `>` removed only for mboxrd body lines | byte assertions for both dialects |
| exact physical offsets | separator, embedded RFC, headers, and body use half-open source ranges | committed fixture assertions |
| raw RFC preservation | bounded copy streams directly from the source range | round-trip tests |
| ordinary, duplicate, and folded headers | ordered header array with source ranges and unfolding | translated tests |
| RFC 2047 common encoded words | Q and B decoding, adjacent-word whitespace rule, explicit charset defect | translated tests |
| MIME parameters and attachments | quoted parameters, escaped quoted text, RFC 2231 single extended values, filename/name | multipart fixture and tests |
| multipart structure | nesting, digest defaults, preamble, epilogue, exact boundary suffix checks | translated tests |
| encapsulated messages | `message/rfc822` becomes a child message | translated test |
| transfer encodings | 7bit/8bit/binary pass-through, base64, quoted-printable | valid and malformed tests |
| malformed input | typed defects retain the raw source instead of dropping the message | CPython defect cases |
| EOF | final unterminated line/message is emitted; empty/non-mbox input emits no records | translated tests |
| input error | D `File` read/seek/write errors remain errors and do not become EOF | direct `File` operations, no catch-and-relabel path |

MIME inspection consumes one bounded RFC message buffer. Mailbox enumeration
and Gmail-bound raw copying remain streaming and never materialize the complete
mailbox.
