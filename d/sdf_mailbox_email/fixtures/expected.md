# Expected boundaries and preservation evidence

The values below are zero-based half-open physical byte offsets.  They are
generated from the checked-in original bytes, not normalized text.

## `ambiguous-from.mbox`

| Record | Separator | Embedded physical RFC bytes | RFC body | Boundary evidence |
| --- | ---: | ---: | ---: | --- |
| 1 | `[0, 52)` | `[52, 216)` | `[104, 216)` | The postmark-shaped line at offset 147 is rejected because its next line is not a field; the separator at 216 is accepted because the next line starts `From:`. |
| 2 | `[216, 266)` | `[266, 327)` | `[315, 327)` | EOF terminates the final message. |

Logical preservation for record 1 changes only the body line prefix
`>From escaped body line\n` to `From escaped body line\n`.  All other
embedded RFC bytes remain identical.  The record retains its physical range
as separate evidence.

## `folded-multipart.mbox`

| Record | Separator | Embedded physical RFC bytes | RFC body | Preservation evidence |
| --- | ---: | ---: | ---: | --- |
| 1 | `[0, 51)` | `[51, 368)` | `[159, 368)` | No mboxrd escapes occur, so logical RFC bytes exactly equal the recorded physical range. |

The MIME tree has two children.  The first is `text/plain`; the second is an
attachment named `two-bytes.bin` whose decoded payload is bytes `00 01`.

SHA-256 anchors: `ambiguous-from.mbox` is
`3fcc20cfa9d8478285252a8861ba8f622c19b6aa95c47b4fb9a597dc3968c274`;
`folded-multipart.mbox` is
`9579a5b45f464214c7508a7210ef8a06ecafef7dd5233533810bd9bc027767f7`.
