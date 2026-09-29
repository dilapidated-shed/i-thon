# Expected boundaries and preservation evidence

Offsets are zero-based and half-open.

## `ambiguous-from.mbox`

| Record | Separator | Embedded physical RFC bytes | RFC body | Evidence |
| --- | ---: | ---: | ---: | --- |
| 1 | `[0, 52)` | `[52, 147)` | `[104, 147)` | `>From escaped body line` stays body data and loses one `>` only in logical mboxrd output. |
| 2 | `[147, 184)` | `[184, 216)` | `[216, 216)` | The invalid-looking `From nobody ...` line still starts a message; absence of a blank header separator leaves an empty classified body range. |
| 3 | `[216, 266)` | `[266, 327)` | `[315, 327)` | EOF terminates the final message. |

The three-record result follows CPython `mailbox.mbox._generate_toc`, which
does not validate the postmark or require a following header.

## `folded-multipart.mbox`

| Record | Separator | Embedded physical RFC bytes | RFC body | Evidence |
| --- | ---: | ---: | ---: | --- |
| 1 | `[0, 51)` | `[51, 368)` | `[159, 368)` | No mboxrd escapes occur, so logical RFC bytes equal the recorded physical range. |

The MIME tree has two children. The first is `text/plain`; the second is an
attachment named `two-bytes.bin` whose decoded payload is `00 01`.

SHA-256:

- `ambiguous-from.mbox`: `3fcc20cfa9d8478285252a8861ba8f622c19b6aa95c47b4fb9a597dc3968c274`
- `folded-multipart.mbox`: `9579a5b45f464214c7508a7210ef8a06ecafef7dd5233533810bd9bc027767f7`
