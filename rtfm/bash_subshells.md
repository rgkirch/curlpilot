$() preserves the exit status; you just have to use it in a statement that has no status of its own, such as an assignment.

output=$(inner)

After this, $? would contain the exit status of inner, and you can use all sorts of checks for it:

output=$(inner) || exit $?
echo $output

Or:

if ! output=$(inner); then
    exit $?
fi
echo $output

Or:

if output=$(inner); then
    echo $output
else
    exit $?
fi

(Note: A bare exit without arguments is equivalent to exit $? – that is, it exits with the last command's exit status. I used the second form only for clarity.)
