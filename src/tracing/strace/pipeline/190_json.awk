#!/usr/bin/gawk -f

@include "json.awk"

BEGIN {
    FS = "\037"
    OFS = ""
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
