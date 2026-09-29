module sdfmail.model;

enum MboxDialect {
    mboxRd,
    mboxO,
    mboxCl,
    mboxCl2,
}

enum DefectKind {
    invalidHeader,
    missingHeaderBodySeparator,
    firstHeaderLineIsContinuation,
    misplacedEnvelopeHeader,
    noBoundaryInMultipart,
    startBoundaryNotFound,
    closeBoundaryNotFound,
    invalidMultipartContentTransferEncoding,
    excessiveMimeNesting,
    invalidBase64Characters,
    invalidBase64Padding,
    invalidBase64Length,
    invalidQuotedPrintable,
    invalidEncodedWord,
    unknownCharset,
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
    ulong key;
    ByteRange separator;
    ByteRange sourceMessage;
    ByteRange headers;
    ByteRange messageBody;
    string envelopeSender;
    bool separatorPrecededByBlankLine;
}

struct MimePart {
    Header[] headers;
    ByteRange source;
    ByteRange body;
    ByteRange preamble;
    ByteRange epilogue;
    bool hasPreamble;
    bool hasEpilogue;
    string contentType;
    string transferEncoding;
    string contentDisposition;
    string charset;
    string filename;
    MimePart[] children;
    Defect[] defects;
}
