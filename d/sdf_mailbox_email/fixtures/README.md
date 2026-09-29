# Byte-exact mbox fixtures

Each `.mbox` file is an original physical mailbox byte sequence, committed
unchanged.  The companion `expected.md` records the physical offsets and the
logical RFC-message result after the one mboxrd unescape mandated by the
format; `translated-results.md` retains the actual command result.  Fixtures use LF deliberately: the translated reader also accepts
CRLF physical lines, and the tests cover MIME folding independently.

`ambiguous-from.mbox` distinguishes an escaped body `>From ` line, a
postmark-shaped body line followed by a non-header (not a separator), and a
postmark-shaped line followed by a header (a separator).

`folded-multipart.mbox` retains a folded RFC header, multipart framing, a
base64 attachment, and the exact raw body bytes.
