# Provenance record

## Original program and upstream

The original retained implementation is CPython's standard-library mailbox
and RFC/MIME stack, not the earlier stand-alone D indexer:

| Role | Retained upstream source | Retained upstream tests |
| --- | --- | --- |
| mbox format and source offsets | `Lib/mailbox.py` (`mbox`, `_mboxMMDF`, `MboxMessage`) | `Lib/test/test_mailbox.py` |
| streamed RFC parsing | `Lib/email/feedparser.py`, `Lib/email/parser.py` | `Lib/test/test_email/test_parser.py` |
| headers, MIME tree and message semantics | `Lib/email/message.py`, `Lib/email/errors.py` | `Lib/test/test_email/test_message.py`, `test_defect_handling.py` |
| content-transfer encodings | `Lib/email/base64mime.py`, `Lib/email/quoprimime.py` | the `Lib/test/test_email/` fixture corpus |

The active SDF source repository is
[`dilapidated-shed/i-thon`](https://github.com/dilapidated-shed/i-thon), whose
README identifies it as the retained CPython 3.16.0a0 tree.  The original
source is therefore a composition of the CPython modules above rather than an
unrelated mail library or a single independent executable.

## Exact copied tree

The translation branch starts at commit
`e3287f631f3c88ed80191aa222e7fc4ba91edd17`, which has the same object ID in
`python/cpython` and `dilapidated-shed/i-thon`.  Its subject is
`gh-155869: Fix data loss in dbm.dumb.reorganize() (GH-155872)` and its parent
is `1a52eaedce6f1d32cdb5ee18ecec74cfd82d5550`.

At that commit the relevant retained objects are:

| Object | Git object ID |
| --- | --- |
| `Lib/mailbox.py` | `99426220154360b707a531335e0f318e404078e2` |
| `Lib/email/` | `5d7f423134022fd44e6b016f4f00ee35feb37884` |
| `Lib/test/test_mailbox.py` | `019c699bff55c4242fd42f90685d4f907195872d` |
| `Lib/test/test_email/` | `75774e7373173a87065d5071de5e88c48902aba9` |

## Local modifications and corpus completeness

Before this branch, `git status --short --branch` was clean and the relevant
paths had no local delta from commit `e3287f…`.  The source-tree identity is
proven by the identical commit object, not inferred from similar files.

The copied tree contains every listed implementation module, the full mailbox
test module, and the complete `Lib/test/test_email/` directory.  It is complete
enough for the SDF mbox-to-importable-message translation.  No supposed copied
source is missing, so translation proceeded.
