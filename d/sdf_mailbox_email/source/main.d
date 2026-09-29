module main;

import std.stdio : File, stderr, stdout;

import sdfmail.mbox : scanMbox;
import sdfmail.model : MboxDialect, MboxRecord;

int main(string[] arguments) {
    if (arguments.length != 2) {
        stderr.writeln("usage: sdf-mailbox-email MAILBOX");
        return 2;
    }
    try {
        auto source = File(arguments[1], "rb");
        size_t number;
        scanMbox(source, MboxDialect.mboxRd, (in MboxRecord record) {
            stdout.writeln(++number, '\t', record.sourceMessage.start, '\t',
                    record.sourceMessage.end, '\t', record.messageBody.start, '\t',
                    record.messageBody.end, '\t', record.envelopeSender);
        });
        return 0;
    } catch (Exception error) {
        stderr.writeln(error.msg);
        return 1;
    }
}
