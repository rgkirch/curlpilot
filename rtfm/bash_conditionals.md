# Bash Conditional Expressions: [[ ... ]]

The `[[ ... ]]` construct is a Bash keyword that provides an enhanced and more robust way to evaluate conditional expressions compared to the older `[ ... ]` (test) command.

**Key Advantages:**
- **No Word Splitting:** Variables do not need to be quoted to prevent errors if they contain spaces. `[[ $var == "some string" ]]` is safe.
- **Pattern Matching:** The `==` operator performs glob-style pattern matching.
- **Regular Expressions:** The `=~` operator provides full regular expression matching.

---
## String Comparisons

### `STRING1 == STRING2`
True if `STRING1` matches the glob pattern `STRING2`. The `=` operator is an identical synonym.
```bash
filename="document.pdf"
if [[ $filename == *.pdf ]]; then
  echo "It's a PDF file."
fi
```

### `STRING1 != STRING2`
True if `STRING1` does not match the pattern `STRING2`.
```bash
if [[ $HOSTNAME != "localhost" ]]; then
  echo "Not on the local machine."
fi
```

### `-z STRING`
True if the length of `STRING` is zero (empty).
```bash
if [[ -z "$password" ]]; then
  echo "Error: Password is empty."
fi
```

### `-n STRING`
True if the length of `STRING` is not zero.
```bash
if [[ -n "$username" ]]; then
  echo "Username is present."
fi
```

### `STRING1 < STRING2`
True if `STRING1` sorts before `STRING2` lexicographically based on the current locale.
```bash
if [[ "alpha" < "beta" ]]; then
  echo "alpha comes before beta."
fi
```

### `STRING1 > STRING2`
True if `STRING1` sorts after `STRING2` lexicographically.
```bash
if [[ "zeta" > "gamma" ]]; then
  echo "zeta comes after gamma."
fi
```

---
## Regular Expression Matching

### `STRING =~ REGEX`
True if `STRING` matches the POSIX extended regular expression `REGEX`.
```bash
email="user@example.com"
if [[ $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "Valid email format."
fi
```

---
## File & Directory Tests

### `-e FILE`
True if `FILE` exists (can be a file, directory, symlink, etc.).
```bash
if [[ -e "/etc/hosts" ]]; then
  echo "/etc/hosts exists."
fi
```

### `-f FILE`
True if `FILE` exists and is a regular file.
```bash
if [[ -f "script.sh" ]]; then
  echo "It's a file."
fi
```

### `-d FILE`
True if `FILE` exists and is a directory.
```bash
if [[ -d "/home/user" ]]; then
  echo "It's a directory."
fi
```

### `-h FILE` or `-L FILE`
True if `FILE` exists and is a symbolic link.
```bash
if [[ -L "/usr/bin/python" ]]; then
  echo "Python is a symlink."
fi
```

### `-r FILE`
True if `FILE` exists and is readable by the current user.
```bash
if [[ -r "config.ini" ]]; then
  content=$(<config.ini)
fi
```

### `-w FILE`
True if `FILE` exists and is writable by the current user.
```bash
if [[ -w "output.log" ]]; then
  echo "Data" >> output.log
fi
```

### `-x FILE`
True if `FILE` exists and is executable by the current user.
```bash
if [[ -x "./run.sh" ]]; then
  ./run.sh
fi
```

### `-s FILE`
True if `FILE` exists and its size is greater than zero.
```bash
if [[ -s "data.csv" ]]; then
  echo "Data file is not empty."
fi
```

### `FILE1 -nt FILE2`
True if `FILE1` is newer than `FILE2` (based on modification timestamp).
```bash
if [[ "app.js" -nt "app.min.js" ]]; then
  echo "Source is newer, need to rebuild."
fi
```

### `FILE1 -ot FILE2`
True if `FILE1` is older than `FILE2`.
```bash
if [[ "archive.zip" -ot "source.txt" ]]; then
  echo "Archive is out of date."
fi
```

### `FILE1 -ef FILE2`
True if `FILE1` and `FILE2` are hard links to the same file (refer to the same inode).
```bash
if [[ "/path/a" -ef "/path/b" ]]; then
  echo "Both are the same file."
fi
```

---
## Variable & Shell Option Tests

### `-v VAR`
True if the shell variable `VAR` is set (has been assigned any value, including an empty string).
```bash
if [[ -v DEBUG_MODE ]]; then
  echo "Debug mode is enabled."
fi
```

### `-R VAR`
True if the shell variable `VAR` is set and is a name reference.
```bash
declare -n ref=my_var
if [[ -R ref ]]; then
  echo "'ref' is a nameref."
fi
```

### `-o OPTION`
True if the shell option `OPTION` is enabled. You can see options with `shopt`.
```bash
# Check if 'noclobber' is on
if [[ -o noclobber ]]; then
  echo "Overwrite protection is on."
fi
```

---
## Numeric Comparisons

These operators require integer arguments. For floating-point or more complex math, use `(( ... ))`.

### `INT1 -eq INT2`
True if `INT1` is equal to `INT2`.
```bash
if [[ $count -eq 0 ]]; then
  echo "Count is zero."
fi
```

### `INT1 -ne INT2`
True if `INT1` is not equal to `INT2`.
```bash
if [[ $EUID -ne 0 ]]; then
  echo "Not running as root."
fi
```

### `INT1 -gt INT2`
True if `INT1` is greater than `INT2`.
```bash
if [[ $age -gt 18 ]]; then
  echo "Is an adult."
fi
```

### `INT1 -ge INT2`
True if `INT1` is greater than or equal to `INT2`.
```bash
if [[ $retries -ge 5 ]]; then
  echo "Max retries reached."
fi
```

### `INT1 -lt INT2`
True if `INT1` is less than `INT2`.
```bash
if [[ $items -lt 10 ]]; then
  echo "Inventory is low."
fi
```

### `INT1 -le INT2`
True if `INT1` is less than or equal to `INT2`.
```bash
if [[ $temp -le 0 ]]; then
  echo "It's freezing!"
fi
```

---
## Combining Expressions

Expressions can be combined using logical operators.

### `! EXPRESSION`
Logical NOT. True if `EXPRESSION` is false.
```bash
if [[ ! -d "$backup_dir" ]]; then
  mkdir -p "$backup_dir"
fi
```

### `EXPR1 && EXPR2`
Logical AND. True if both expressions are true.
```bash
if [[ -r "$file" && -s "$file" ]]; then
  echo "File is readable and not empty."
fi
```

### `EXPR1 || EXPR2`
Logical OR. True if either expression is true.
```bash
if [[ "$user" == "admin" || "$user" == "root" ]]; then
  echo "User has root privileges."
fi
```

### `( EXPRESSION )`
Grouping. Used to override the default order of precedence (`&&` is higher than `||`).
```bash
if [[ ( "$ext" == "jpg" || "$ext" == "png" ) && $size -gt 1024 ]]; then
  echo "Large image file found."
fi
```
