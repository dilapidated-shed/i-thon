module sdfmail.mime;

import std.ascii : toLower;
import std.string : indexOf;

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
        if (line.length >= 5 && line[0 .. 5] == cast(const(ubyte)[]) "From ") {
            result.defects ~= Defect(DefectKind.misplacedEnvelopeHeader,
                    ByteRange(at, end), "envelope From_ line appears inside RFC headers");
            at = end;
            continue;
        }
        size_t colon;
        while (colon < line.length && line[colon] != ':') colon++;
        if (colon == line.length) {
            // email.feedparser stops header parsing at the first line which
            // cannot be a field and retains that line as body bytes.
            result.defects ~= Defect(DefectKind.missingHeaderBodySeparator,
                    ByteRange(at, end), "body began without a blank header separator");
            result.bodyStart = at;
            return result;
        } else if (colon == 0) {
            result.defects ~= Defect(DefectKind.invalidHeader, ByteRange(at, end),
                    "header field name is empty");
        } else {
            result.headers ~= Header(lowerAscii(line[0 .. colon]), text(trim(line[colon + 1 .. $])),
                    ByteRange(at, end));
        }
        at = end;
    }
    result.bodyStart = limit;
    if (limit > start) result.defects ~= Defect(DefectKind.missingHeaderBodySeparator,
            ByteRange(start, limit), "header block ended at EOF without a blank line");
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

private string percentDecode(string encoded) {
    ubyte[] result;
    for (size_t i; i < encoded.length; ++i) {
        if (encoded[i] == '%' && i + 2 < encoded.length &&
                hexValue(cast(ubyte) encoded[i + 1]) >= 0 &&
                hexValue(cast(ubyte) encoded[i + 2]) >= 0) {
            result ~= cast(ubyte)((hexValue(cast(ubyte) encoded[i + 1]) << 4) |
                    hexValue(cast(ubyte) encoded[i + 2]));
            i += 2;
        } else result ~= cast(ubyte) encoded[i];
    }
    return text(result);
}

private string parameter(string header, string wanted) {
    string ordinary;
    string extended;
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
        string found;
        if (quoted) {
            while (at < header.length && header[at] != '"') {
                if (header[at] == '\\' && at + 1 < header.length) at++;
                found ~= header[at++];
            }
        } else {
            auto valueStart = at;
            while (at < header.length && header[at] != ';') at++;
            found = text(trim(cast(const(ubyte)[]) header[valueStart .. at]));
        }
        if (quoted && at < header.length) at++;
        auto name = lowerAscii(trim(cast(const(ubyte)[]) header[nameStart .. nameEnd]));
        if (name == wanted) ordinary = found;
        if (name == wanted ~ "*") {
            auto firstQuote = found.indexOf('\'');
            auto secondQuote = firstQuote < 0 ? -1 : found.indexOf('\'', firstQuote + 1);
            extended = percentDecode(secondQuote < 0 ? found : found[secondQuote + 1 .. $]);
        }
    }
    return extended.length ? extended : ordinary;
}

private bool boundaryLine(scope const(ubyte)[] line, string boundary, out bool closing) {
    auto logical = stripLineEnd(line);
    if (logical.length < boundary.length + 2 || logical[0] != '-' || logical[1] != '-') return false;
    foreach (i, c; boundary) if (logical[i + 2] != c) return false;
    auto rest = logical[boundary.length + 2 .. $];
    closing = rest.length >= 2 && rest[0 .. 2] == cast(const(ubyte)[]) "--";
    if (closing) rest = rest[2 .. $];
    foreach (c; rest) if (c != ' ' && c != '\t') return false;
    return true;
}

private MimePart parsePart(scope const(ubyte)[] bytes, size_t start, size_t end,
        uint depth, string defaultContentType = "text/plain") {
    MimePart part;
    part.source = ByteRange(start, end);
    auto parsed = parseHeaderBlock(bytes, start, end);
    part.headers = parsed.headers;
    part.defects = parsed.defects;
    part.body.start = parsed.bodyStart;
    part.body.end = end;
    auto contentTypeHeader = value(part.headers, "content-type");
    part.contentType = contentTypeHeader.length == 0 ? defaultContentType : mainValue(contentTypeHeader);
    part.transferEncoding = mainValue(value(part.headers, "content-transfer-encoding"));
    auto dispositionHeader = value(part.headers, "content-disposition");
    part.contentDisposition = mainValue(dispositionHeader);
    part.charset = parameter(contentTypeHeader, "charset");
    part.filename = parameter(dispositionHeader, "filename");
    if (part.filename.length == 0) part.filename = parameter(contentTypeHeader, "name");

    if (depth >= 64) {
        part.defects ~= Defect(DefectKind.excessiveMimeNesting, part.body,
                "MIME nesting exceeded 64 levels");
        return part;
    }
    if (part.contentType == "message/rfc822") {
        if (part.body.start < part.body.end)
            part.children ~= parsePart(bytes, part.body.start, part.body.end, depth + 1);
        return part;
    }
    if (part.contentType.length < 10 || part.contentType[0 .. 10] != "multipart/") return part;
    if (part.transferEncoding.length && part.transferEncoding != "7bit" &&
            part.transferEncoding != "8bit" && part.transferEncoding != "binary")
        part.defects ~= Defect(DefectKind.invalidMultipartContentTransferEncoding,
                part.body, "multipart body has an invalid transfer encoding");
    auto boundary = parameter(contentTypeHeader, "boundary");
    if (boundary.length == 0) {
        part.defects ~= Defect(DefectKind.noBoundaryInMultipart, part.body,
                "multipart content type has no boundary parameter");
        return part;
    }

    size_t at = part.body.start;
    size_t childStart = size_t.max;
    size_t firstBoundary = size_t.max;
    bool closed;
    auto childDefault = part.contentType == "multipart/digest" ? "message/rfc822" : "text/plain";
    while (at < end) {
        auto lineEndAt = lineEnd(bytes, at, end);
        bool isClosing;
        if (boundaryLine(bytes[at .. lineEndAt], boundary, isClosing)) {
            if (firstBoundary == size_t.max) {
                firstBoundary = at;
                part.preamble = ByteRange(part.body.start, at);
                part.hasPreamble = at > part.body.start;
            }
            if (childStart != size_t.max && childStart <= at)
                part.children ~= parsePart(bytes, childStart, at, depth + 1, childDefault);
            if (isClosing) {
                closed = true;
                part.epilogue = ByteRange(lineEndAt, end);
                part.hasEpilogue = lineEndAt < end;
                break;
            }
            childStart = lineEndAt;
        }
        at = lineEndAt;
    }
    if (firstBoundary == size_t.max)
        part.defects ~= Defect(DefectKind.startBoundaryNotFound, part.body,
                "multipart body has no start boundary");
    else if (!closed) {
        if (childStart != size_t.max && childStart < end)
            part.children ~= parsePart(bytes, childStart, end, depth + 1, childDefault);
        part.defects ~= Defect(DefectKind.closeBoundaryNotFound, part.body,
                "multipart body has no closing boundary");
    }
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
    ubyte[] data;
    size_t padding;
    bool invalidCharacters;
    bool paddingStarted;
    foreach (c; encoded) {
        // Message.get_payload removes physical line endings before decode.
        if (c == '\r' || c == '\n') continue;
        if (c == '=') { paddingStarted = true; padding++; continue; }
        auto value = base64Value(c);
        if (value < 0) { invalidCharacters = true; continue; }
        if (paddingStarted) invalidCharacters = true;
        data ~= c;
    }
    if (data.length % 4 == 1) {
        result.bytes = encoded.dup;
        result.defects ~= Defect(DefectKind.invalidBase64Length,
                ByteRange(0, encoded.length), "base64 data length is one more than a multiple of four");
        return result;
    }
    auto neededPadding = (4 - data.length % 4) % 4;
    bool paddingDefect = padding != neededPadding;
    if (invalidCharacters)
        result.defects ~= Defect(DefectKind.invalidBase64Characters,
                ByteRange(0, encoded.length), "base64 contains ignored non-alphabet bytes");
    if (paddingDefect && !(invalidCharacters && padding >= neededPadding))
        result.defects ~= Defect(DefectKind.invalidBase64Padding,
                ByteRange(0, encoded.length), "base64 padding was missing or misplaced");

    for (size_t i; i < data.length; i += 4) {
        auto remaining = data.length - i;
        auto a = base64Value(data[i]);
        auto b = base64Value(data[i + 1]);
        result.bytes ~= cast(ubyte)((a << 2) | (b >> 4));
        if (remaining >= 3) {
            auto c = base64Value(data[i + 2]);
            result.bytes ~= cast(ubyte)((b << 4) | (c >> 2));
            if (remaining >= 4) {
                auto d = base64Value(data[i + 3]);
                result.bytes ~= cast(ubyte)((c << 6) | d);
            }
        }
    }
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
    auto encoding = lowerAscii(cast(const(ubyte)[]) transferEncoding);
    if (encoding == "base64") return base64Decode(raw);
    if (encoding == "quoted-printable") return quotedPrintableDecode(raw);
    DecodeResult result;
    result.bytes = raw.dup;
    return result;
}

struct HeaderDecodeResult {
    string value;
    Defect[] defects;
}

// Decode RFC 2047 encoded words without changing the retained raw header.
// Adjacent encoded words discard intervening linear whitespace as required by
// the RFC.  UTF-8 and ASCII bytes are returned directly; an unknown charset is
// retained byte-for-byte and reported as a defect.
HeaderDecodeResult decodeHeaderWords(string raw) {
    HeaderDecodeResult result;
    size_t at;
    bool previousWasEncoded;
    while (at < raw.length) {
        auto marker = raw.indexOf("=?", at);
        if (marker < 0) {
            result.value ~= raw[at .. $];
            break;
        }
        auto charsetEnd = raw.indexOf('?', marker + 2);
        auto encodingEnd = charsetEnd < 0 ? -1 : raw.indexOf('?', charsetEnd + 1);
        auto wordEnd = encodingEnd < 0 ? -1 : raw.indexOf("?=", encodingEnd + 1);
        if (charsetEnd < 0 || encodingEnd < 0 || wordEnd < 0) {
            result.value ~= raw[at .. marker + 2];
            result.defects ~= Defect(DefectKind.invalidEncodedWord,
                    ByteRange(marker, raw.length), "unterminated RFC 2047 encoded word");
            at = marker + 2;
            previousWasEncoded = false;
            continue;
        }
        auto between = raw[at .. marker];
        bool onlyWhitespace = true;
        foreach (c; between) if (c != ' ' && c != '\t' && c != '\r' && c != '\n') onlyWhitespace = false;
        if (!(previousWasEncoded && onlyWhitespace)) result.value ~= between;

        auto charset = lowerAscii(cast(const(ubyte)[]) raw[marker + 2 .. charsetEnd]);
        auto encoding = lowerAscii(cast(const(ubyte)[]) raw[charsetEnd + 1 .. encodingEnd]);
        auto encoded = cast(const(ubyte)[]) raw[encodingEnd + 1 .. wordEnd];
        DecodeResult decoded;
        if (encoding == "b") decoded = base64Decode(encoded);
        else if (encoding == "q") {
            ubyte[] q = encoded.dup;
            foreach (ref c; q) if (c == '_') c = ' ';
            decoded = quotedPrintableDecode(q);
        } else {
            result.value ~= raw[marker .. wordEnd + 2];
            result.defects ~= Defect(DefectKind.invalidEncodedWord,
                    ByteRange(marker, wordEnd + 2), "unknown RFC 2047 transfer encoding");
            at = wordEnd + 2;
            previousWasEncoded = false;
            continue;
        }
        result.defects ~= decoded.defects;
        if (charset != "utf-8" && charset != "utf8" && charset != "us-ascii" && charset != "ascii")
            result.defects ~= Defect(DefectKind.unknownCharset,
                    ByteRange(marker + 2, charsetEnd), "encoded word charset is not decoded");
        result.value ~= text(decoded.bytes);
        at = wordEnd + 2;
        previousWasEncoded = true;
    }
    return result;
}
