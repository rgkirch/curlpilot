https://stackoverflow.com/questions/3348443/a-confusion-about-array-versus-array-in-the-context-of-a-bash-comple


(This is an expansion of my comment on Kaleb Pederson's answer -- see that answer for a more general treatment of [@] vs [*].)

When bash (or any similar shell) parses a command line, it splits it into a series of "words" (which I will call "shell-words" to avoid confusion later). Generally, shell-words are separated by spaces (or other whitespace), but spaces can be included in a shell-word by escaping or quoting them. The difference between [@] and [*]-expanded arrays in double-quotes is that "${myarray[@]}" leads to each element of the array being treated as a separate shell-word, while "${myarray[*]}" results in a single shell-word with all of the elements of the array separated by spaces (or whatever the first character of IFS is).

Usually, the [@] behavior is what you want. Suppose we have perls=(perl-one perl-two) and use ls "${perls[*]}" -- that's equivalent to ls "perl-one perl-two", which will look for single file named perl-one perl-two, which is probably not what you wanted. ls "${perls[@]}" is equivalent to ls "perl-one" "perl-two", which is much more likely to do something useful.

Providing a list of completion words (which I will call comp-words to avoid confusion with shell-words) to compgen is different; the -W option takes a list of comp-words, but it must be in the form of a single shell-word with the comp-words separated by spaces. Note that command options that take arguments always (at least as far as I know) take a single shell-word -- otherwise there'd be no way to tell when the arguments to the option end, and the regular command arguments (/other option flags) begin.

In more detail:

perls=(perl-one perl-two)
compgen -W "${perls[*]} /usr/bin/perl" -- ${cur}

is equivalent to:

compgen -W "perl-one perl-two /usr/bin/perl" -- ${cur}

...which does what you want. On the other hand,

perls=(perl-one perl-two)
compgen -W "${perls[@]} /usr/bin/perl" -- ${cur}

is equivalent to:

compgen -W "perl-one" "perl-two /usr/bin/perl" -- ${cur}

...which is complete nonsense: "perl-one" is the only comp-word attached to the -W flag, and the first real argument -- which compgen will take as the string to be completed -- is "perl-two /usr/bin/perl". I'd expect compgen to complain that it's been given extra arguments ("--" and whatever's in $cur), but apparently it just ignores them.
