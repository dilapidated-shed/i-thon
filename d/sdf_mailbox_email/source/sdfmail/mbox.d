module sdfmail.mbox;

import std.exception : enforce;
import std.stdio : File;

import sdfmail.model;

private enum ScanState { first, headers, body, pending }

private bool isDigit(ubyte c) { return c >= '0' && c <= '9'; }

private bool startsWith(scope const(ubyte)[] value, string prefix) {
    if (value.length < prefix.length) return false;
    foreach (i, c; prefix) if (value[i] != c) return false;
    return true;
}

private int decimal(scope const(ubyte)[] value) {
    if (value.length == 0 || value.length > 4) return -1;
    int result;
    foreach (c; value) {
        if (!isDigit(c)) return -1;
        result = result * 10 + c - '0';
    }
    return result;
}

private bool oneOf(scope const(ubyte)[] value, scope const(string)[] choices) {
    foreach (choice; choices) {
        if (value.length != choice.length) continue;
        bool equal = true;
        foreach (i, c; choice) if (value[i] != c) equal = false;
        if (equal) return true;
    }
    return false;
}

// This is intentionally the same conservative shape check used by the prior
// D indexer: a bare From_ line alone is never enough evidence for a boundary.
private bool postmark(scope const(ubyte)[] line) {
    if (line.length == 0 || line[$ - 1] != '\n') return false;
    if (line.length >= 2 && line[$ - 2] == '\r') line = line[0 .. $ - 2];
    else line = line[0 .. $ - 1];
    if (!startsWith(line, "From ")) return false;

    size_t cursor = 5;
    while (cursor < line.length && line[cursor] != ' ') cursor++;
    if (cursor == 5 || cursor == line.length) return false;
    cursor++;
    while (cursor < line.length && line[cursor] == ' ') cursor++;
    if (cursor + 3 >= line.length || !oneOf(line[cursor .. cursor + 3],
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])) return false;
    cursor += 3;
    if (cursor >= line.length || line[cursor++] != ' ') return false;
    if (cursor + 3 >= line.length || !oneOf(line[cursor .. cursor + 3],
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])) return false;
    cursor += 3;
    if (cursor >= line.length || line[cursor++] != ' ') return false;
    while (cursor < line.length && line[cursor] == ' ') cursor++;
    auto dayStart = cursor;
    while (cursor < line.length && isDigit(line[cursor])) cursor++;
    auto day = decimal(line[dayStart .. cursor]);
    if (day < 1 || day > 31 || cursor >= line.length || line[cursor++] != ' ') return false;
    if (cursor + 8 > line.length) return false;
    auto time = line[cursor .. cursor + 8];
    if (time[2] != ':' || time[5] != ':' || decimal(time[0 .. 2]) > 23 ||
            decimal(time[3 .. 5]) > 59 || decimal(time[6 .. 8]) > 60) return false;
    cursor += 8;
    if (cursor >= line.length || line[cursor++] != ' ') return false;
    while (cursor < line.length && line[cursor] == ' ') cursor++;
    auto tokenStart = cursor;
    while (cursor < line.length && line[cursor] != ' ') cursor++;
    if (decimal(line[tokenStart .. cursor]) >= 1900 && cursor == line.length) return true;
    while (cursor < line.length && line[cursor] == ' ') cursor++;
    return cursor + 4 == line.length && decimal(line[cursor .. $]) >= 1900;
}

private bool blank(scope const(ubyte)[] line) {
    return line == cast(const(ubyte)[]) "\n" || line == cast(const(ubyte)[]) "\r\n";
}

private bool headerField(scope const(ubyte)[] line) {
    size_t i;
    while (i < line.length && line[i] != ':') {
        auto c = line[i];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                (c >= '0' && c <= '9') || c == '-')) return false;
        i++;
    }
    return i > 0 && i < line.length;
}

private string sender(scope const(ubyte)[] separator) {
    size_t end = 5;
    while (end < separator.length && separator[end] != ' ') end++;
    auto result = new char[end - 5];
    foreach (i, c; separator[5 .. end]) result[i] = cast(char) c;
    return result.idup;
}

// Scan only holds one physical line at a time.  It records source byte ranges
// rather than materializing messages or the mailbox.  The caller can reopen a
// bounded source range later for MIME parsing or Gmail import.
void scanMbox(ref File source, MboxDialect dialect,
        scope void delegate(in MboxRecord) emit) {
    enforce(dialect == MboxDialect.mboxRd || dialect == MboxDialect.mboxO,
            "sdf-mailbox-email: mboxcl and mboxcl2 Content-Length framing were intentionally discarded for the SDF mbox path");
    auto state = ScanState.first;
    MboxRecord record;
    ulong position;
    ulong lineStart;
    ulong pendingStart;
    ulong pendingEnd;
    ubyte[] pendingSeparator;
    ScanState pendingPrevious;

    void begin(ulong separatorStart, ulong separatorEnd, scope const(ubyte)[] line,
            bool ambiguous) {
        record = MboxRecord.init;
        record.separator = ByteRange(separatorStart, separatorEnd);
        record.sourceMessage.start = separatorEnd;
        record.headers.start = separatorEnd;
        record.envelopeSender = sender(line);
        record.boundaryWasAmbiguous = ambiguous;
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
    }

    void considerSeparator(scope const(ubyte)[] line, ulong start, ulong end) {
        pendingStart = start;
        pendingEnd = end;
        pendingSeparator = line.dup;
        pendingPrevious = state;
        state = ScanState.pending;
    }

    void accept(scope const(ubyte)[] line, ulong start, ulong end) {
        final switch (state) {
            case ScanState.first:
                enforce(postmark(line), "sdf-mailbox-email: first line is not an mbox From_ separator");
                begin(start, end, line, false);
                break;
            case ScanState.headers:
                if (postmark(line)) considerSeparator(line, start, end);
                else consumeHeader(line, start, end);
                break;
            case ScanState.body:
                if (postmark(line)) considerSeparator(line, start, end);
                break;
            case ScanState.pending:
                if (headerField(line)) {
                    state = pendingPrevious;
                    finish(pendingStart);
                    emit(record);
                    begin(pendingStart, pendingEnd, pendingSeparator, true);
                    consumeHeader(line, start, end);
                } else {
                    record.rejectedSeparatorCandidates++;
                    state = pendingPrevious;
                    accept(line, start, end);
                }
                break;
        }
    }

    while (true) {
        auto line = source.readln();
        if (line.length == 0) break;
        position += line.length;
        accept(cast(const(ubyte)[]) line, lineStart, position);
        lineStart = position;
    }
    if (state == ScanState.pending) record.rejectedSeparatorCandidates++;
    if (state != ScanState.first) {
        if (state == ScanState.pending) state = pendingPrevious;
        finish(position);
        emit(record);
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
