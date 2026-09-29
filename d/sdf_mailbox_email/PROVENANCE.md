# Provenance record

## Original program and upstream

The retained original is CPython's mailbox and RFC/MIME input path in
[`dilapidated-shed/i-thon`](https://github.com/dilapidated-shed/i-thon):

| Role | Retained source | Retained tests |
| --- | --- | --- |
| mbox framing and byte ranges | `Lib/mailbox.py`: `_singlefileMailbox`, `_mboxMMDF`, `mbox` | `Lib/test/test_mailbox.py` |
| incremental RFC parsing | `Lib/email/feedparser.py`, `Lib/email/parser.py` | `Lib/test/test_email/test_parser.py` |
| message and MIME semantics | `Lib/email/message.py`, `Lib/email/errors.py` | `test_message.py`, `test_defect_handling.py` |
| transfer and encoded-word decoding | `Lib/email/_encoded_words.py`, `base64mime.py`, `quoprimime.py` | `Lib/test/test_email/` and its data corpus |

The repository is the user's retained CPython tree. It is unrelated to
`one-room-schoolhouse/mailR`, which sends SMTP mail from R, and unrelated to
ICU's retained curl IMAP/POP and outgoing-MIME code.

## Exact copied tree

The branch starts from
`e3287f631f3c88ed80191aa222e7fc4ba91edd17`, an object shared with upstream
`python/cpython`. Its subject is `gh-155869: Fix data loss in
dbm.dumb.reorganize() (GH-155872)` and its parent is
`1a52eaedce6f1d32cdb5ee18ecec74cfd82d5550`.

| Object | Git object ID |
| --- | --- |
| `Lib/mailbox.py` | `99426220154360b707a531335e0f318e404078e2` |
| `Lib/email/` | `5d7f423134022fd44e6b016f4f00ee35feb37884` |
| `Lib/test/test_mailbox.py` | `019c699bff55c4242fd42f90685d4f907195872d` |
| `Lib/test/test_email/` | `75774e7373173a87065d5071de5e88c48902aba9` |

The copied corpus contains the implementation, full mailbox test module,
complete email tests, and their fixture directory.

## Local changes to the retained original

The relevant Python paths have no delta from the starting CPython commit. The D
translation lives under `d/sdf_mailbox_email/`; it does not edit the retained
Python source or tests.

## Retained program boundary

The SDF project retained the read-only traditional-mbox input path: enumerate
messages, preserve physical ranges, obtain logical RFC bytes, parse headers and
MIME, decode import-relevant transfer encodings, and retain defects. Mutation
and unrelated mailbox stores were already outside this path; the exact list is
in `INTENTIONALLY_DISCARDED.md`.

## Translation audit correction

The first D commit added a sender/date/following-header heuristic before
accepting a `From ` line. CPython's `mbox._generate_toc` does no such check:
every physical line beginning `From ` starts a message. The current translation
removes that redesign and ports the source behavior. The adversarial fixture
now yields three messages, including the deliberately malformed middle one.
