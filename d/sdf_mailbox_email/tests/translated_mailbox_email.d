module translated_mailbox_email;

import std.stdio : File;

import sdfmail.mbox : scanMbox, unquoteMboxRd;
import sdfmail.mime : decodeBody, parseMessage;
import sdfmail.model : DefectKind, MboxDialect, MboxRecord;

private MboxRecord[] recordsFor(string bytes) {
    auto temporary = File.tmpfile();
    temporary.rawWrite(cast(const(ubyte)[]) bytes);
    temporary.seek(0);
    MboxRecord[] records;
    scanMbox(temporary, MboxDialect.mboxRd, (in MboxRecord record) {
        records ~= record;
    });
    return records;
}

private bool hasDefect(typeof(parseMessage(cast(const(ubyte)[]) "")) part, DefectKind wanted) {
    foreach (defect; part.defects) if (defect.kind == wanted) return true;
    return false;
}

unittest {
    // Ported coverage intent from Lib/test/test_mailbox.py: distinguish an
    // embedded From_ body line from a subsequent mbox message boundary while
    // keeping the original physical byte ranges.
    enum mailbox =
        "From alice@example.invalid Mon Jan  1 00:00:00 2024\n" ~
        "From: Alice <alice@example.invalid>\n" ~
        "Subject: first\n" ~
        "\n" ~
        "ordinary body line\n" ~
        ">From escaped body line\n" ~
        "From nobody Mon Jan  1 00:00:01 2024\n" ~
        "this is body text, not a header\n" ~
        "From bob@example.invalid Tue Jan  2 03:04:05 2024\n" ~
        "From: Bob <bob@example.invalid>\n" ~
        "Subject: second\n" ~
        "\n" ~
        "second body\n";

    auto records = recordsFor(mailbox);
    assert(records.length == 2);
    assert(records[0].separator.start == 0 && records[0].separator.end == 52);
    assert(records[0].sourceMessage.start == 52 && records[0].sourceMessage.end == 216);
    assert(records[0].messageBody.start == 104 && records[0].messageBody.end == 216);
    assert(records[0].rejectedSeparatorCandidates == 1);
    assert(records[1].separator.start == 216 && records[1].separator.end == 266);
    assert(records[1].sourceMessage.start == 266 && records[1].sourceMessage.end == mailbox.length);

    auto physical = cast(const(ubyte)[]) mailbox[records[0].sourceMessage.start .. records[0].sourceMessage.end];
    auto logical = unquoteMboxRd(physical, records[0].messageBody.start - records[0].sourceMessage.start);
    assert(cast(string) logical ==
        "From: Alice <alice@example.invalid>\nSubject: first\n\nordinary body line\n" ~
        "From escaped body line\nFrom nobody Mon Jan  1 00:00:01 2024\n" ~
        "this is body text, not a header\n");
}

unittest {
    // Ported coverage intent from Lib/test/test_email/test_message.py and
    // test_parser.py: unfolded headers, multipart shape, transfer decoding,
    // attachment metadata, and byte retention.
    enum raw =
        "From: MIME <mime@example.invalid>\r\n" ~
        "Subject: folded\r\n" ~
        " subject\r\n" ~
        "Content-Type: multipart/mixed; boundary=\"outer\"\r\n" ~
        "\r\n" ~
        "preamble\r\n" ~
        "--outer\r\n" ~
        "Content-Type: text/plain\r\n" ~
        "\r\n" ~
        "plain text\r\n" ~
        "--outer\r\n" ~
        "Content-Type: application/octet-stream\r\n" ~
        "Content-Transfer-Encoding: base64\r\n" ~
        "Content-Disposition: attachment; filename=\"two-bytes.bin\"\r\n" ~
        "\r\n" ~
        "AAE=\r\n" ~
        "--outer--\r\n";
    auto message = parseMessage(cast(const(ubyte)[]) raw);
    assert(message.headers[1].value == "folded subject");
    assert(message.contentType == "multipart/mixed");
    assert(message.children.length == 2);
    assert(message.children[1].filename == "two-bytes.bin");
    assert(message.children[1].transferEncoding == "base64");
    auto decoded = decodeBody(cast(const(ubyte)[]) raw[message.children[1].body.start .. message.children[1].body.end],
            message.children[1].transferEncoding);
    assert(decoded.defects.length == 0);
    assert(decoded.bytes == cast(const(ubyte)[]) "\x00\x01");
}

unittest {
    // Ported coverage intent from Lib/test/test_email/test_defect_handling.py:
    // preserve malformed bytes and surface a defect instead of throwing them away.
    enum malformed = "Broken-Header\n\tcontinued\nbody without separator\n";
    auto message = parseMessage(cast(const(ubyte)[]) malformed);
    assert(hasDefect(message, DefectKind.malformedHeader));
    assert(hasDefect(message, DefectKind.missingHeaderBodySeparator));

    auto badBase64 = decodeBody(cast(const(ubyte)[]) "not*base64", "base64");
    assert(badBase64.defects.length == 1);
    auto badQuotedPrintable = decodeBody(cast(const(ubyte)[]) "bad=QZ", "quoted-printable");
    assert(badQuotedPrintable.defects.length == 1);
}

void main() {}
