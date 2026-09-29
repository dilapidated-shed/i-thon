# Translated D fixture results

The following output was produced by the committed D command after compiling
the translation locally.  Columns are record number, physical RFC-message
start/end, physical body start/end, and boundary classification.

```text
$ sdf-mailbox-email fixtures/ambiguous-from.mbox
1       52      216     104     216     first
2       266     327     315     327     ambiguous

$ sdf-mailbox-email fixtures/folded-multipart.mbox
1       51      368     159     368     first
```

The unit tests separately assert the mboxrd logical-byte result for the first
fixture and decode the multipart attachment of the second.  Together with the
physical original and SHA-256 anchors in `expected.md`, this supplies both
physical-range and logical-preservation evidence.
