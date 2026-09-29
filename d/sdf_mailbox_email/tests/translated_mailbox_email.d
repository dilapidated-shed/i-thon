module translated_mailbox_email;

import std.exception : assertThrown;
import std.file : SpanMode, dirEntries, read;
import std.path : buildPath, dirName;
import std.stdio : File;
import std.string : indexOf;

import sdfmail.mbox : copyLogicalRfcMessage, scanMbox, unquoteMboxRd;
import sdfmail.mime : DecodeResult, decodeBody, decodeHeaderWords, parseMessage;
import sdfmail.model : DefectKind, MboxDialect, MboxRecord, MimePart;

private MboxRecord[] recordsFor(string bytes, MboxDialect dialect = MboxDialect.mboxRd) {
    auto temporary = File.tmpfile();
    temporary.rawWrite(cast(const(ubyte)[]) bytes);
    temporary.seek(0);
    MboxRecord[] records;
    scanMbox(temporary, dialect, (in MboxRecord record) { records ~= record; });
    return records;
}

private string fixturePath(string name) {
    return buildPath(dirName(__FILE_FULL_PATH__), "..", "fixtures", name);
}

private string upstreamEmailDataPath() {
    return buildPath(dirName(__FILE_FULL_PATH__), "..", "..", "..",
            "Lib", "test", "test_email", "data");
}

private bool hasDefect(in MimePart part, DefectKind wanted) {
    foreach (defect; part.defects) if (defect.kind == wanted) return true;
    return false;
}

private bool hasDecodeDefect(in DecodeResult result, DefectKind wanted) {
    foreach (defect; result.defects) if (defect.kind == wanted) return true;
    return false;
}

private ubyte[] copiedLogical(string mailbox, in MboxRecord record, MboxDialect dialect) {
    auto source = File.tmpfile();
    source.rawWrite(cast(const(ubyte)[]) mailbox);
    source.seek(0);
    auto sink = File.tmpfile();
    copyLogicalRfcMessage(source, sink, record, dialect);
    sink.seek(0);
    ubyte[] result;
    ubyte[64] buffer;
    while (true) {
        auto got = sink.rawRead(buffer[]);
        if (got.length == 0) break;
        result ~= got;
    }
    return result;
}

unittest {
    // CPython Lib/mailbox.py: mbox._generate_toc accepts every physical
    // "From " line. It does not apply date or next-header heuristics.
    enum mailbox =
        "ignored preamble\n" ~
        "From alice@example.invalid Mon Jan  1 00:00:00 2024\n" ~
        "From: Alice <alice@example.invalid>\nSubject: first\n\nbody\n" ~
        "From not-a-date\n" ~
        "not a header\n" ~
        "From bob@example.invalid Tue Jan  2 03:04:05 2024\n" ~
        "From: Bob <bob@example.invalid>\nSubject: second\n\nsecond body\n";
    auto records = recordsFor(mailbox);
    auto first = mailbox.indexOf("From alice");
    auto middle = mailbox.indexOf("From not-a-date");
    auto last = mailbox.indexOf("From bob");
    assert(records.length == 3);
    assert(records[0].key == 0 && records[0].separator.start == first);
    assert(records[0].sourceMessage.end == middle);
    assert(records[1].separator.start == middle && records[1].sourceMessage.end == last);
    assert(records[2].separator.start == last && records[2].sourceMessage.end == mailbox.length);
}

unittest {
    // Exercise the retained upstream email fixture corpus directly.  These
    // samples include nested MIME, malformed headers, unusual line endings,
    // attachments, and historical parser regressions.
    size_t count;
    foreach (entry; dirEntries(upstreamEmailDataPath(), "msg_*.txt", SpanMode.shallow)) {
        auto bytes = cast(ubyte[]) read(entry.name);
        auto message = parseMessage(bytes);
        assert(message.source.start == 0 && message.source.end == bytes.length);
        count++;
    }
    assert(count >= 47);
}

unittest {
    // The committed bytes are exercised directly, so the receipt is tied to
    // the fixture rather than to a separately retyped test string.
    auto ambiguousBytes = cast(ubyte[]) read(fixturePath("ambiguous-from.mbox"));
    auto ambiguous = recordsFor(cast(string) ambiguousBytes);
    assert(ambiguous.length == 3);
    assert(ambiguous[0].separator.start == 0 && ambiguous[0].separator.end == 52);
    assert(ambiguous[0].sourceMessage.start == 52 && ambiguous[0].sourceMessage.end == 147);
    assert(ambiguous[1].separator.start == 147 && ambiguous[1].separator.end == 184);
    assert(ambiguous[1].sourceMessage.start == 184 && ambiguous[1].sourceMessage.end == 216);
    assert(ambiguous[2].separator.start == 216 && ambiguous[2].separator.end == 266);
    assert(ambiguous[2].sourceMessage.start == 266 && ambiguous[2].sourceMessage.end == 327);

    auto multipartBytes = cast(ubyte[]) read(fixturePath("folded-multipart.mbox"));
    auto multipart = recordsFor(cast(string) multipartBytes);
    assert(multipart.length == 1);
    assert(multipart[0].sourceMessage.start == 51 && multipart[0].sourceMessage.end == 368);
    auto message = parseMessage(multipartBytes[multipart[0].sourceMessage.start .. multipart[0].sourceMessage.end]);
    assert(message.children.length == 2);
    assert(message.children[1].filename == "two-bytes.bin");
}

unittest {
    // One LF-only blank line separating messages belongs to neither embedded
    // RFC message, matching mailbox.mbox._generate_toc.
    enum mailbox = "From a\nSubject: one\n\nbody\n\nFrom b\nSubject: two\n\nlast";
    auto records = recordsFor(mailbox);
    auto second = mailbox.indexOf("From b");
    assert(records.length == 2);
    assert(records[0].sourceMessage.end == second - 1);
    assert(!records[0].separatorPrecededByBlankLine);
    assert(records[1].separatorPrecededByBlankLine);
    assert(records[1].sourceMessage.end == mailbox.length);
}

unittest {
    assert(recordsFor("").length == 0);
    assert(recordsFor("preamble only\nSubject: not a mailbox\n").length == 0);
    auto records = recordsFor("From x\nSubject: no body separator");
    assert(records.length == 1);
    assert(records[0].headers.end == records[0].sourceMessage.end);
    assert(records[0].messageBody.start == records[0].sourceMessage.end);
    assertThrown!Exception(recordsFor("From x\n\n", MboxDialect.mboxCl));
}

unittest {
    enum mailbox = "From x\nSubject: quoted\n\n>From one\n>>From two\nplain\n";
    auto record = recordsFor(mailbox)[0];
    auto physical = cast(const(ubyte)[]) mailbox[record.sourceMessage.start .. record.sourceMessage.end];
    auto logical = unquoteMboxRd(physical,
            record.messageBody.start - record.sourceMessage.start);
    assert(cast(string) logical == "Subject: quoted\n\nFrom one\n>From two\nplain\n");
    assert(cast(string) copiedLogical(mailbox, record, MboxDialect.mboxRd) == cast(string) logical);
    assert(cast(string) copiedLogical(mailbox, record, MboxDialect.mboxO) == cast(string) physical);
}

unittest {
    enum raw =
        "From: MIME <mime@example.invalid>\r\n" ~
        "Subject: folded\r\n subject\r\n" ~
        "X-Duplicate: first\r\nX-Duplicate: second\r\n" ~
        "Content-Type: multipart/mixed; boundary=\"outer\"\r\n\r\n" ~
        "preamble\r\n--outer\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nplain text\r\n" ~
        "--outer\r\nContent-Type: application/octet-stream\r\n" ~
        "Content-Transfer-Encoding: base64\r\n" ~
        "Content-Disposition: attachment; filename*=utf-8''two%20bytes.bin\r\n\r\n" ~
        "AAE=\r\n--outer--\r\nepilogue\r\n";
    auto message = parseMessage(cast(const(ubyte)[]) raw);
    assert(message.headers[1].value == "folded subject");
    assert(message.headers[2].value == "first" && message.headers[3].value == "second");
    assert(message.contentType == "multipart/mixed");
    assert(message.hasPreamble && message.hasEpilogue);
    assert(message.children.length == 2);
    assert(message.children[0].charset == "utf-8");
    assert(message.children[1].filename == "two bytes.bin");
    auto decoded = decodeBody(cast(const(ubyte)[])
            raw[message.children[1].body.start .. message.children[1].body.end],
            message.children[1].transferEncoding);
    assert(decoded.defects.length == 0 && decoded.bytes == cast(const(ubyte)[]) "\x00\x01");
}

unittest {
    // FeedParser stops at the first non-header line and retains it in the body.
    enum raw = "Subject: test\nnot a header\nTo: still body\n\nbody\n";
    auto message = parseMessage(cast(const(ubyte)[]) raw);
    assert(message.headers.length == 1);
    assert(message.body.start == raw.indexOf("not a header"));
    assert(hasDefect(message, DefectKind.missingHeaderBodySeparator));

    auto continuation = parseMessage(cast(const(ubyte)[]) " continuation\nSubject: x\n\nbody\n");
    assert(hasDefect(continuation, DefectKind.firstHeaderLineIsContinuation));
    auto invalid = parseMessage(cast(const(ubyte)[]) ": bad\nSubject: x\n\nbody\n");
    assert(hasDefect(invalid, DefectKind.invalidHeader));
    auto envelope = parseMessage(cast(const(ubyte)[]) "From stray\nSubject: x\n\nbody\n");
    assert(hasDefect(envelope, DefectKind.misplacedEnvelopeHeader));
}

unittest {
    auto noBoundary = parseMessage(cast(const(ubyte)[])
            "Content-Type: multipart/mixed\n\nbody\n");
    assert(hasDefect(noBoundary, DefectKind.noBoundaryInMultipart));

    auto noStart = parseMessage(cast(const(ubyte)[])
            "Content-Type: multipart/mixed; boundary=x\n\nbody\n");
    assert(hasDefect(noStart, DefectKind.startBoundaryNotFound));

    auto noClose = parseMessage(cast(const(ubyte)[])
            "Content-Type: multipart/mixed; boundary=x\n\n--x\n\nbody\n");
    assert(noClose.children.length == 1);
    assert(hasDefect(noClose, DefectKind.closeBoundaryNotFound));

    auto badCte = parseMessage(cast(const(ubyte)[])
            "Content-Type: multipart/mixed; boundary=x\nContent-Transfer-Encoding: base64\n\n--x--\n");
    assert(hasDefect(badCte, DefectKind.invalidMultipartContentTransferEncoding));
}

unittest {
    enum raw =
        "Content-Type: multipart/digest; boundary=x\n\n" ~
        "--x\n\nSubject: nested\n\ninside\n--x--\n";
    auto digest = parseMessage(cast(const(ubyte)[]) raw);
    assert(digest.children.length == 1);
    assert(digest.children[0].contentType == "message/rfc822");
    assert(digest.children[0].children.length == 1);
    assert(digest.children[0].children[0].headers[0].value == "nested");

    // A boundary prefix followed by other text is ordinary body data.
    auto strict = parseMessage(cast(const(ubyte)[])
            "Content-Type: multipart/mixed; boundary=x\n\n--xBAD\nbody\n--x--\n");
    assert(strict.children.length == 0);
}

unittest {
    auto base64 = decodeBody(cast(const(ubyte)[]) "TWFu\r\n", "BASE64");
    assert(cast(string) base64.bytes == "Man" && base64.defects.length == 0);
    assert(hasDecodeDefect(decodeBody(cast(const(ubyte)[]) "TW*u", "base64"),
            DefectKind.invalidBase64Characters));
    assert(hasDecodeDefect(decodeBody(cast(const(ubyte)[]) "TQ=", "base64"),
            DefectKind.invalidBase64Padding));
    assert(hasDecodeDefect(decodeBody(cast(const(ubyte)[]) "abcde", "base64"),
            DefectKind.invalidBase64Length));
    auto ignoredCharacter = decodeBody(cast(const(ubyte)[]) "dm\x01k===", "base64");
    assert(cast(string) ignoredCharacter.bytes == "vi");
    assert(ignoredCharacter.defects.length == 1);
    assert(ignoredCharacter.defects[0].kind == DefectKind.invalidBase64Characters);
    auto impossibleLength = decodeBody(cast(const(ubyte)[]) "abcde", "base64");
    assert(cast(string) impossibleLength.bytes == "abcde");
    auto missingPadding = decodeBody(cast(const(ubyte)[]) "dmk", "base64");
    assert(cast(string) missingPadding.bytes == "vi");
    assert(hasDecodeDefect(missingPadding, DefectKind.invalidBase64Padding));

    auto quoted = decodeBody(cast(const(ubyte)[]) "one=20two=\r\nthree", "quoted-printable");
    assert(cast(string) quoted.bytes == "one twothree");
    assert(hasDecodeDefect(decodeBody(cast(const(ubyte)[]) "bad=QZ", "quoted-printable"),
            DefectKind.invalidQuotedPrintable));
}

unittest {
    auto subject = decodeHeaderWords("=?utf-8?Q?SDF_mail?= =?utf-8?B?4pyT?=");
    assert(subject.value == "SDF mail✓");
    assert(subject.defects.length == 0);
    auto unknown = decodeHeaderWords("=?x-private?Q?raw=20bytes?=");
    assert(unknown.value == "raw bytes");
    bool sawUnknownCharset;
    foreach (defect; unknown.defects)
        if (defect.kind == DefectKind.unknownCharset) sawUnknownCharset = true;
    assert(sawUnknownCharset);
    auto broken = decodeHeaderWords("before =?utf-8?Q?unterminated");
    assert(broken.defects.length == 1 && broken.value == "before =?utf-8?Q?unterminated");
}

void main() {}
