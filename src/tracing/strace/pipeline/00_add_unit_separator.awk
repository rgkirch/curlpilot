#!/usr/bin/awk -f

BEGIN {
    OFS="\037"
    
}

{
    if(match($0, /^([0-9]+)<([^>]+)> ([0-9]+\.[0-9]+) ([^(]+)\((.*)\) = (0)/, fields))
        print fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    else if(match($0, /^([0-9]+)<([^>]+)> ([0-9]+\.[0-9]+) ([^(]+)\((.*)\) = (0)/, fields))

}
