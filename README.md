# curlpilot

This directory contains scripts for interacting with the Copilot API.

## `login.bash`

This script handles authentication and login with the Copilot API. It should be run to ensure your session is authenticated before using other `curlpilot` scripts that require API access. Upon successful login, it saves the Personal Access Token (PAT) to `$HOME/.config/curlpilot/github_pat.txt` and the Copilot session token to `$HOME/.config/curlpilot/token.txt`.

*   **Personal Access Token (PAT):** A PAT is an alternative to using your password for authentication to GitHub (or other services). It's a string of characters that grants specific permissions to your account.
*   **Session Token:** A session token is a temporary credential that authenticates your current session with the Copilot API, allowing subsequent requests to be made without re-authenticating.

## `chat.bash`

This script is designed to send git diffs to Copilot for review. It takes a literal text message as an argument, which is then passed to Copilot. This message should be a plain, descriptive string.

**Example usage:**

```bash
./chat.bash "Tell me one fun animal fact."
```

**Example Response:**

```
Sea otters hold hands while they sleep so they don’t drift apart from each other in the water!
```

## Feature Ideas

*   **Portable conversations:** All conversation data is stored locally, allowing portability across systems by simply syncing the relevant files.
*   **Search previous user prompts:** Implement Ctrl+r functionality to search through previous user prompts. User prompts should be saved in a raw, unsummarized format.
*   **Embedding model for conversation history paths:** Utilize an embedding model to generate folder paths for conversation history, enabling more intelligent organization.
*   **Customizable prompts from file:** Allow users to define and customize prompts by reading them from a file located at `~/.config/curlpilot/`.
*   **Easy tool integration:** Simplify tool integration by allowing any new script placed under `~/.config/curlpilot/tools/` to automatically function as a tool.

## notes
instead of

``` bash
jq -j -n --arg key "$JQ_FILTER_KEY" 'inputs | try (.choices[0][$key].content? // empty)'
```

i'm doing

``` bash
jq -j -n 'inputs | .choices[0] | .delta.content // .message.content'
```

which might be ok

### read vs variable expansion

- read
``` bash
# The pipe '|' sends the string to the { ... } block's standard input
printf '{"json":"payload"}\0{"status":"ok"}' | {
  # First 'read' consumes everything up to the null byte
  IFS= read -r -d '' part1

  # Second 'read' consumes the rest of the stream
  IFS= read -r part2

  echo "Part 1: $part1"
  echo "Part 2: $part2"
}
```

- expansian
``` bash
# The string is first stored entirely in a variable
full_string=$'{"json":"payload"}\0{"status":"ok"}'
# 1. Remove the null byte and everything *after* it
part1="${full_string%$'\0'*}"
# 2. Remove everything *up to and including* the null byte
part2="${full_string#*$'\0'}"

echo "Part 1: $part1"
echo "Part 2: $part2"
```
