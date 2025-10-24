#!/usr/bin/gawk -f

BEGIN {
    FS = "\037"
    OFS = ""
}

function json_escape(str) {
    gsub(/\\/, "\\\\", str)
    gsub(/"/, "\\\"", str)
    gsub(/\n/, "\\n", str)
    gsub(/\r/, "\\r", str)
    gsub(/\t/, "\\t", str)
    gsub(/\f/, "\\f", str)
    gsub(/\b/, "\\b", str)
    return str
}

{
    if ($1 == "json") {
        printf "{"
        for (i = 2; i <= NF; i += 2) {
            if (i + 1 <= NF) {
                if (i > 2) {
                    printf ", "
                }
                printf "\"%s\": \"%s\"", json_escape($(i)), json_escape($(i+1))
            }
        }
        printf "}\n"
    } else {
        print $0
    }
}

