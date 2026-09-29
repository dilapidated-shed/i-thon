module sdfmail.mime;

import std.ascii : toLower;

import sdfmail.model;

private struct HeaderBlock {
    Header[] headers;
    size_t bodyStart;
    Defect[] defects;
}

private bool equalFold(scope const(ubyte)[] bytes, string text) {
    if (bytes.length != text.length) return false;
    foreach (i, c; text) if (toLower(cast(char) bytes[i]) != c) return false;
    return true;
}

private string lowerAscii(scope const(ubyte)[] bytes) {
    auto result = new char[bytes.length];
    foreach (i, c; bytes) result[i] = toLower(cast(char) c);
    return result.idup;
}

private const(ubyte)[] stripLineEnd(const(ubyte)[] bytes) {
    if (bytes.length > 0 && bytes[$ - 1] == '\n') bytes = bytes[0 .. $ - 1];
    if (bytes.length > 0 && bytes[$ - 1] == '\r') bytes = bytes[0 .. $ - 1];
    return bytes;
}

private const(ubyte)[] trim(const(ubyte)[] bytes) {
    size_t first;
    while (first < bytes.length && (bytes[first] == ' ' || bytes[first] == '\t' ||
            bytes[first] == '\r' || bytes[first] == '\n')) first++;
    size_t last = bytes.length;
    while (last > first && (bytes[last - 1] == ' ' || bytes[last - 1] == '\t' ||
            bytes[last - 1] == '\r' || bytes[last - 1] == '\n')) last--;
    return bytes[first .. last];
}

private string text(scope const(ubyte)[] bytes) {
    auto result = new char[bytes.length];
    foreach (i, c; bytes) result[i] = cast(char) c;
    return result.idup;
}

private size_t lineEnd(scope const(ubyte)[] bytes, size_t start, size_t limit) {
    auto at = start;
    while (at < limit && bytes[at] != '\n') at++;
    return at < limit ? at + 1 : at;
}

private HeaderBlock parseHeaderBlock(scope const(ubyte)[] bytes, size_t start, size_t limit) {
    HeaderBlock result;
    size_t at = start;
    while (at < limit) {
        auto end = lineEnd(bytes, at, limit);
        auto line = stripLineEnd(bytes[at .. end]);
        if (line.length == 0) {
            result.bodyStart = end;
            return result;
        }
        if (line[0] == ' ' || line[0] == '\t') {
            if (result.headers.length == 0) {
                result.defects ~= Defect(DefectKind.firstHeaderLineIsContinuation,
                        ByteRange(at, end), "first header line is a continuation");
            } else {
                result.headers[$ - 1].value ~= " " ~ text(trim(line));
                result.headers[$ - 1].source.end = end;
            }
            at = end;
            continue;
        }
        size_t colon;
        while (colon < line.length && line[colon] != ':') colon++;
        if (colon == 0 || colon == line.length) {
            result.defects ~= Defect(DefectKind.malformedHeader, ByteRange(at, end),
                    "header field has no colon");
        } else {
            result.headers ~= Header(lowerAscii(line[0 .. colon]), text(trim(line[colon + 1 .. $])),
                    ByteRange(at, end));
        }
        at = end;
    }
    result.bodyStart = limit;
    result.defects ~= Defect(DefectKind.missingHeaderBodySeparator, ByteRange(start, limit),
            "header block ended at EOF without a blank line");
    return result;
}

private string value(Header[] headers, string name) {
    foreach (header; headers) if (header.name == name) return header.value;
    return "";
}

private string mainValue(string header) {
    size_t end;
    while (end < header.length && header[end] != ';') end++;
    return lowerAscii(trim(cast(const(ubyte)[]) header[0 .. end]));
}

private string parameter(string header, string wanted) {
    size_t at;
    while (at < header.length) {
        while (at < header.length && (header[at] == ';' || header[at] == ' ' || header[at] == '\t')) at++;
        auto nameStart = at;
        while (at < header.length && header[at] != '=' && header[at] != ';') at++;
        auto nameEnd = at;
        if (at == header.length || header[at] != '=') {
            while (at < header.length && header[at] != ';') at++;
            continue;
        }
        at++;
        bool quoted = at < header.length && header[at] == '"';
        if (quoted) at++;
        auto valueStart = at;
        if (quoted) while (at < header.length && header[at] != '"') at++;
        else while (at < header.length && header[at] != ';') at++;
        auto valueEnd = at;
        if (quoted && at < header.length) at++;
        auto name = lowerAscii(trim(cast(const(ubyte)[]) header[nameStart .. nameEnd]));
        if (name == wanted) return header[valueStart .. valueEnd].dup;
    }
    return "";
}

private bool boundaryLine(scope const(ubyte)[] line, string boundary, out bool closing) {
    auto logical = stripLineEnd(line);
    if (logical.length < boundary.length + 2 || logical[0] != '-' || logical[1] != '-') return false;
    foreach (i, c; boundary) if (logical[i + 2] != c) return false;
    auto rest = logical[boundary.length + 2 .. $];
    closing = rest.length >= 2 && rest[0 .. 2] == cast(const(ubyte)[]) "--";
    return rest.length == 0 || closing || rest[0] == ' ' || rest[0] == '\t';
}

private MimePart parsePart(scope const(ubyte)[] bytes, size_t start, size_t end, uint depth) {
    MimePart part;
    part.source = ByteRange(start, end);
    auto parsed = parseHeaderBlock(bytes, start, end);
    part.headers = parsed.headers;
    part.defects = parsed.defects;
    part.body.start = parsed.bodyStart;
    part.body.end = end;
    auto contentTypeHeader = value(part.headers, "content-type");
    part.contentType = contentTypeHeader.length == 0 ? "text/plain" : mainValue(contentTypeHeader);
    part.transferEncoding = mainValue(value(part.headers, "content-transfer-encoding"));
    part.filename = parameter(value(part.headers, "content-disposition"), "filename");
    if (part.filename.length == 0) part.filename = parameter(contentTypeHeader, "name");

    if (depth >= 64 || part.contentType.length < 10 || part.contentType[0 .. 10] != "multipart/") return part;
    auto boundary = parameter(contentTypeHeader, "boundary");
    if (boundary.length == 0) {
        part.defects ~= Defect(DefectKind.missingMultipartBoundary, part.body,
                "multipart content type has no boundary parameter");
        return part;
    }

    size_t at = part.body.start;
    size_t childStart = size_t.max;
    bool closed;
    while (at < end) {
        auto lineEndAt = lineEnd(bytes, at, end);
        bool isClosing;
        if (boundaryLine(bytes[at .. lineEndAt], boundary, isClosing)) {
            if (childStart != size_t.max && childStart <= at) part.children ~= parsePart(bytes, childStart, at, depth + 1);
            if (isClosing) { closed = true; break; }
            childStart = lineEndAt;
        }
        at = lineEndAt;
    }
    if (!closed) part.defects ~= Defect(DefectKind.missingClosingMultipartBoundary, part.body,
            "multipart body has no closing boundary");
    return part;
}

MimePart parseMessage(scope const(ubyte)[] bytes) {
    return parsePart(bytes, 0, bytes.length, 0);
}

private int base64Value(ubyte c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

struct DecodeResult {
    ubyte[] bytes;
    Defect[] defects;
}

private DecodeResult base64Decode(scope const(ubyte)[] encoded) {
    DecodeResult result;
    int[] quantum;
    foreach (c; encoded) {
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
        if (c == '=') quantum ~= -2;
        else {
            auto value = base64Value(c);
            if (value < 0) {
                result.defects ~= Defect(DefectKind.invalidBase64, ByteRange(0, encoded.length), "base64 contains a non-alphabet byte");
                return result;
            }
            quantum ~= value;
        }
        if (quantum.length != 4) continue;
        if (quantum[0] < 0 || quantum[1] < 0 || quantum[2] == -2 && quantum[3] != -2) {
            result.defects ~= Defect(DefectKind.invalidBase64, ByteRange(0, encoded.length), "invalid base64 padding");
            return result;
        }
        result.bytes ~= cast(ubyte)((quantum[0] << 2) | (quantum[1] >> 4));
        if (quantum[2] != -2) result.bytes ~= cast(ubyte)((quantum[1] << 4) | (quantum[2] >> 2));
        if (quantum[3] != -2 && quantum[2] != -2) result.bytes ~= cast(ubyte)((quantum[2] << 6) | quantum[3]);
        quantum.length = 0;
    }
    if (quantum.length != 0) result.defects ~= Defect(DefectKind.invalidBase64, ByteRange(0, encoded.length), "incomplete base64 quantum");
    return result;
}

private int hexValue(ubyte c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

private DecodeResult quotedPrintableDecode(scope const(ubyte)[] encoded) {
    DecodeResult result;
    for (size_t i = 0; i < encoded.length; ++i) {
        if (encoded[i] != '=') { result.bytes ~= encoded[i]; continue; }
        if (i + 1 < encoded.length && encoded[i + 1] == '\n') { i += 1; continue; }
        if (i + 2 < encoded.length && encoded[i + 1] == '\r' && encoded[i + 2] == '\n') { i += 2; continue; }
        if (i + 2 >= encoded.length || hexValue(encoded[i + 1]) < 0 || hexValue(encoded[i + 2]) < 0) {
            result.defects ~= Defect(DefectKind.invalidQuotedPrintable, ByteRange(i, i + 1), "invalid quoted-printable escape");
            result.bytes ~= encoded[i];
            continue;
        }
        result.bytes ~= cast(ubyte)((hexValue(encoded[i + 1]) << 4) | hexValue(encoded[i + 2]));
        i += 2;
    }
    return result;
}

DecodeResult decodeBody(scope const(ubyte)[] raw, string transferEncoding) {
    if (transferEncoding == "base64") return base64Decode(raw);
    if (transferEncoding == "quoted-printable") return quotedPrintableDecode(raw);
    DecodeResult result;
    result.bytes = raw.dup;
    return result;
}
