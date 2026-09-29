# Feature-parity record

This record measures the retained read-only SDF mbox slice against the CPython
sources identified in `PROVENANCE.md`.

| CPython behavior | D module | Evidence |
| --- | --- | --- |
| Stream physical input without loading mailbox | `sdfmail.mbox.scanMbox` | one `File.readln` physical line; records are ranges |
| traditional mbox `From ` framing | `sdfmail.mbox` postmark and pending-state logic | ambiguous fixture and translated test |
| escaped mboxrd `From ` | `unquoteMboxRd`, `copyLogicalRfcMessage` | byte-preservation assertion |
| exact physical offsets | `ByteRange` / `MboxRecord` | fixture offsets and assertions |
| logical raw RFC preservation | `copyLogicalRfcMessage` | range-copy algorithm and fixture evidence |
| normal and folded headers | `sdfmail.mime.parseHeaderBlock` | multipart translated test |
| MIME multipart tree and attachment metadata | `sdfmail.mime.parseMessage` | multipart translated test |
| base64 and quoted-printable | `sdfmail.mime.decodeBody` | attachment and malformed-encoding tests |
| malformed-message retention | defects in `sdfmail.model` and parser | malformed-header test |
| EOF distinctions | mbox scan finalization and MIME missing-separator/closing-boundary defects | translated tests and fixture EOF record |

The current D API intentionally exposes parsed structure separately from raw
bytes.  Parsing never replaces the recorded physical message range; Gmail
import can use the logical raw stream while tools inspect the MIME tree.

Features outside the retained SDF scope are listed explicitly in
`INTENTIONALLY_DISCARDED.md`; none are silently substituted with another mail
library.
