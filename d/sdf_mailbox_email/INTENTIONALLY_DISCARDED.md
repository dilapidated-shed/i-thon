# Intentionally discarded features

The retained SDF path reads a traditional mailbox and emits importable RFC
messages. The existing project scope discarded these CPython mailbox features:

- mailbox creation, append, replacement, deletion, rewriting, locking, mode and
  ownership preservation;
- Maildir, MH, Babyl and MMDF stores and their folder APIs;
- outgoing message construction and serialization;
- SMTP, IMAP, POP, authentication, and network transport;
- `mboxcl` and `mboxcl2` `Content-Length` framing.

`mboxcl` and `mboxcl2` fail explicitly. The reader does not reinterpret them
as mboxrd.

The retained path includes the difficult input behavior: CPython-compatible
`From ` framing, mboxrd quoting, exact offsets, raw RFC bytes, ordered and folded
headers, encoded words, MIME nesting, `message/rfc822`, transfer encodings,
attachments, malformed input defects, and EOF behavior.
