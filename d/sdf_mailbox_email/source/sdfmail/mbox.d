module sdfmail.mbox;

import std.exception : enforce;
import std.stdio : File;

import sdfmail.model;

private enum ScanState { beforeFirst, headers, body }

private bool startsWith(scope const(ubyte)[] value, string prefix) {
    if (value.length < prefix.length) return false;
    foreach (i, c; prefix) if (value[i] != c) return false;
    return true;
}

private bool blank(scope const(ubyte)[] line) {
    return line == cast(const(ubyte)[]) "\n" || line == cast(const(ubyte)[]) "\r\n";
}

private string sender(scope const(ubyte)[] separator) {
    size_t end = 5;
    while (end < separator.length && separator[end] != ' ') end++;
    auto result = new char[end - 5];
    foreach (i, c; separator[5 .. end]) result[i] = cast(char) c;
    return result.idup;
}

// This is the read-only translation of mailbox.mbox._generate_toc.  CPython
// deliberately recognizes every physical line beginning "From " as a new
// message.  It does not validate the sender, date, or following header.  A
// valid mboxrd producer must quote body lines of that shape.
void scanMbox(ref File source, MboxDialect dialect,
        scope void delegate(in MboxRecord) emit) {
    enforce(dialect == MboxDialect.mboxRd || dialect == MboxDialect.mboxO,
            "sdf-mailbox-email: mboxcl and mboxcl2 Content-Length framing were intentionally discarded for the SDF mbox path");
    auto state = ScanState.beforeFirst;
    MboxRecord record;
    ulong position;
    ulong lineStart;
    ulong nextKey;
    bool lastWasEmpty;

    void begin(ulong separatorStart, ulong separatorEnd, scope const(ubyte)[] line,
            bool precededByBlankLine) {
        record = MboxRecord.init;
        record.key = nextKey++;
        record.separator = ByteRange(separatorStart, separatorEnd);
        record.sourceMessage.start = separatorEnd;
        record.headers.start = separatorEnd;
        record.envelopeSender = sender(line);
        record.separatorPrecededByBlankLine = precededByBlankLine;
        state = ScanState.headers;
    }

    void consumeHeader(scope const(ubyte)[] line, ulong start, ulong end) {
        if (blank(line)) {
            record.headers.end = start;
            record.messageBody.start = end;
            state = ScanState.body;
        }
        // Do not reject malformed fields here: the MIME parser retains them
        // with defects, and Gmail migration still needs their exact bytes.
    }

    void finish(ulong end) {
        record.sourceMessage.end = end;
        if (state == ScanState.headers) {
            record.headers.end = end;
            record.messageBody.start = end;
        }
        record.messageBody.end = end;
        emit(record);
    }

    while (true) {
        auto line = source.readln();
        if (line.length == 0) break;
        position += line.length;
        auto bytes = cast(const(ubyte)[]) line;
        if (startsWith(bytes, "From ")) {
            if (state != ScanState.beforeFirst) {
                auto stop = lastWasEmpty ? lineStart - 1 : lineStart;
                finish(stop);
            }
            begin(lineStart, position, bytes, lastWasEmpty);
            lastWasEmpty = false;
        } else if (state != ScanState.beforeFirst) {
            if (state == ScanState.headers) consumeHeader(bytes, lineStart, position);
            lastWasEmpty = bytes == cast(const(ubyte)[]) "\n";
        }
        lineStart = position;
    }
    if (state != ScanState.beforeFirst) {
        auto stop = lastWasEmpty ? position - 1 : position;
        finish(stop);
    }
}

// mboxrd escaping applies only after the RFC header/body separator.  This
// function turns a bounded embedded-message buffer into the exact logical RFC
// bytes that Gmail needs, while the MboxRecord still preserves physical bytes.
ubyte[] unquoteMboxRd(scope const(ubyte)[] source, size_t bodyOffset) {
    ubyte[] result;
    size_t lineStart;
    for (size_t i = 0; i <= source.length; ++i) {
        if (i != source.length && source[i] != '\n') continue;
        auto line = source[lineStart .. i + (i == source.length ? 0 : 1)];
        if (lineStart >= bodyOffset) {
            size_t marks;
            while (marks < line.length && line[marks] == '>') marks++;
            if (marks > 0 && line.length >= marks + 5 &&
                    startsWith(line[marks .. $], "From ")) {
                result ~= line[1 .. $];
            } else result ~= line;
        } else result ~= line;
        lineStart = i + 1;
    }
    return result;
}

// Copy one message directly from the mailbox source to an import sink.  The
// operation never holds the mailbox (or even the whole message) in memory.
// In mboxrd mode it removes exactly one protective '>' from body lines whose
// remaining bytes begin "From "; all headers and every other byte are copied.
void copyLogicalRfcMessage(ref File source, ref File sink, in MboxRecord record,
        MboxDialect dialect) {
    enforce(dialect == MboxDialect.mboxRd || dialect == MboxDialect.mboxO,
            "sdf-mailbox-email: mboxcl and mboxcl2 are not available for copying");
    source.seek(cast(long) record.sourceMessage.start);
    ulong position = record.sourceMessage.start;
    while (position < record.sourceMessage.end) {
        auto line = source.readln();
        enforce(line.length > 0 && position + line.length <= record.sourceMessage.end,
                "sdf-mailbox-email: source range does not end on a physical line boundary");
        auto bytes = cast(const(ubyte)[]) line;
        if (dialect == MboxDialect.mboxRd && position >= record.messageBody.start) {
            size_t marks;
            while (marks < bytes.length && bytes[marks] == '>') marks++;
            if (marks > 0 && bytes.length >= marks + 5 && startsWith(bytes[marks .. $], "From ")) {
                sink.rawWrite(bytes[1 .. $]);
            } else sink.rawWrite(bytes);
        } else sink.rawWrite(bytes);
        position += line.length;
    }
}
