Brendan Gregg's collapsed stack format
If you want a simpler file format to generate and don't care about the units used for each stack, then Brendan Gregg's collapsed stack format is easy to generate and understand.

The format consists of one stack trace per line, with the line ending with a single integer indicating the weight of that sample. Semicolons separate stack frames in the stack trace.

Here's an example profile in that format:

```
main;a;b;c 1
main;a;b;c 1
main;a;b;d 4
main;a;b;c 3
main;a;b 5
```
