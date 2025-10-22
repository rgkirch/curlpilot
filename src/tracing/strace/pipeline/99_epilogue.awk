#!/usr/bin/gawk -f

BEGIN {
    FS = "\037"
}

{
    #print "99" $0
    print $0
}
