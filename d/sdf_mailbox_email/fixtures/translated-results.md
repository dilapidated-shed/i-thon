# Translated D fixture results

Columns are record number, physical RFC start/end, physical body start/end, and
envelope sender.

```text
$ sdf-mailbox-email fixtures/ambiguous-from.mbox
1       52      147     104     147     alice@example.invalid
2       184     216     216     216     nobody
3       266     327     315     327     bob@example.invalid

$ sdf-mailbox-email fixtures/folded-multipart.mbox
1       51      368     159     368     mime@example.invalid
```

The tests read these files directly, assert every range, verify mboxrd logical
bytes, parse the multipart tree, and decode its attachment.
