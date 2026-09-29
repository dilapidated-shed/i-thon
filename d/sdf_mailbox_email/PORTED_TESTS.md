# Translated test record

The D tests use the retained CPython source and tests as behavioral evidence.
They do not use another mail library as an oracle.

| CPython source/test behavior | D coverage |
| --- | --- |
| `mailbox.mbox._generate_toc` recognizes any `From ` line | invalid-date and non-header-following separators |
| `_generate_toc` stop offsets and final empty line | LF separator, EOF with and without final newline |
| `_mboxMMDF.get_bytes` excludes the envelope line | embedded RFC ranges start after `From_` |
| mbox output mangles body `From ` lines | mboxrd unquote and mboxo non-unquote round trips |
| `test_first_line_is_continuation_header` | matching defect with later header retained |
| `test_missing_header_body_separator` | header scan stops and body begins at offending line |
| `test_line_beginning_colon` | invalid-header defect |
| `test_misplaced_envelope` | misplaced-envelope defect |
| `test_bad_padding_in_base64_payload` | decodes recoverable bytes and reports padding |
| `test_invalid_chars_in_base64_payload` | ignores invalid characters and reports them |
| `test_invalid_length_of_base64_payload` | retains undecodable source and reports length |
| `test_missing_ending_boundary` | parses children and reports missing close |
| email multipart/message semantics | nested multipart/digest and `message/rfc822` |
| email header/parameter semantics | folds, duplicates, RFC 2047, quoted and RFC 2231 filename |
| complete upstream `msg_*.txt` corpus | every retained text fixture parses without losing its source range |

The committed `.mbox` files are also read directly by the D tests. Expected
offsets do not come from retyped copies.
