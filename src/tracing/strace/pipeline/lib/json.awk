#!/usr/bin/gawk -f

function json_escape(str) {
    gsub(/\\/, "\\\\", str)
    gsub(/"/, "\\\"", str)
    gsub(/%/, "%%", str)
    gsub(/\n/, "\\n", str)
    gsub(/\r/, "\\r", str)
    gsub(/\t/, "\\t", str)
    gsub(/\f/, "\\f", str)
    gsub(/\b/, "\\b", str)
    return str
}

function print_json(data) {
    printf "{"
    for (i = 1; i <= length(data); i += 2) {
        if (i + 1 <= length(data)) {
            if (i > 1) {
                printf ", "
            }
            printf "\"%s\": \"%s\"", json_escape(data[i]), json_escape(data[i+1])
        }
    }
    printf "}\n"
}
