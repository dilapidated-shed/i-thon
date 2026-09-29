# Intentionally discarded features

The SDF project retained a read-only traditional mbox path.  The following
CPython `mailbox` features were deliberately excluded by that existing project
scope and remain excluded from this independent D branch:

- mailbox mutation, rewriting, locking, ownership preservation and creation;
- Maildir, MH, Babyl and MMDF stores;
- `mboxcl` and `mboxcl2` `Content-Length` framing;
- filesystem mailbox discovery and folder-management APIs;
- outgoing mail construction, SMTP/IMAP/POP transport, and address-book work.

This branch does **not** discard the SDF-relevant mboxrd reader, physical source
offsets, logical raw RFC bytes, headers, folded headers, MIME structure,
transfer encodings, multipart bodies, attachments, malformed-message defects,
or EOF distinctions.

`mboxcl`/`mboxcl2` are rejected explicitly rather than silently treated as
mboxrd.  That keeps a `Content-Length` mailbox from being imported under the
wrong framing rule.
