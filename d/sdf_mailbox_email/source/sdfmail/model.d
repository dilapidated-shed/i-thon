module sdfmail.model;

enum MboxDialect {
    mboxRd,
    mboxO,
    mboxCl,
    mboxCl2,
}

enum DefectKind {
    malformedHeader,
    missingHeaderBodySeparator,
    firstHeaderLineIsContinuation,
    missingMultipartBoundary,
    missingClosingMultipartBoundary,
    invalidBase64,
    invalidQuotedPrintable,
    ambiguousMboxBoundary,
    unsupportedContentLengthFraming,
}

struct ByteRange {
    ulong start;
    ulong end;

    @property ulong length() const { return end - start; }
}

struct Defect {
    DefectKind kind;
    ByteRange location;
    string detail;
}

struct Header {
    string name;
    string value;
    ByteRange source;
}

// sourceMessage is the exact byte range of the embedded RFC message in the
// mailbox.  It excludes the mbox From_ separator.  messageBody begins after
// the embedded header/body separator and is still in source coordinates.
struct MboxRecord {
    ByteRange separator;
    ByteRange sourceMessage;
    ByteRange headers;
    ByteRange messageBody;
    string envelopeSender;
    bool boundaryWasAmbiguous;
    uint rejectedSeparatorCandidates;
}

struct MimePart {
    Header[] headers;
    ByteRange source;
    ByteRange body;
    string contentType;
    string transferEncoding;
    string filename;
    MimePart[] children;
    Defect[] defects;
}
