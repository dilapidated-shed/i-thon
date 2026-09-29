# Byte-exact mbox fixtures

Each `.mbox` file is a physical mailbox byte sequence committed unchanged.
`expected.md` records zero-based half-open ranges and logical mboxrd results.
`translated-results.md` records the D command output.

`ambiguous-from.mbox` proves the retained CPython rule. The escaped
`>From ` body line stays in its message, while each unescaped physical
`From ` line starts another message regardless of date validity or the next
line's shape.

`folded-multipart.mbox` retains a folded header, multipart framing, a base64
attachment, and exact raw body bytes.
