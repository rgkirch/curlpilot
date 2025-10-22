#!/usr/bin/gawk -f

{
    print $0 > "/dev/stderr"
    print $0
}
