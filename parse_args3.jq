# Helpers _parse_cli_token and _coerce_value remain the same.
def _parse_cli_token:
  sub("^--"; "")
  | capture("^(?<key>[^=]+)(=(?<value>.*))?$")
  | .key |= gsub("-"; "_");

def _coerce_value(type):
  if type == "boolean" then toboolean
  elif type == "json" and . != "-" then fromjson
  else .
  end;

# The recursive parsing function.
def _parse_recursive:
  # Base Case: If there are no more arguments, we're done.
  if (.args | length == 0) then
    .spec
  else
    # Recursive Step: Process the head of the list, then recurse on the tail.
    .args[0] as $current_arg |
    .args[1:] as $remaining_args |
    .spec as $current_spec |
    ($current_arg | _parse_cli_token) as $token |

    (
      if $token.value != null then
        { key: $token.key, value: $token.value, consume: 1 }
      else
        $current_spec[$token.key] as $spec_entry |
        if ($remaining_args | length > 0) and ($remaining_args[0] | startswith("--") | not) then
          { key: $token.key, value: $remaining_args[0], consume: 2 }
        else
          {
            key: $token.key,
            value: (if $spec_entry.type == "boolean" then "true" else $spec_entry.default end),
            consume: 1
          }
        end
      end
    ) as $parsed |

    # Create the next state and pass it to the recursive call.
    (
      .spec[$parsed.key].value = ($parsed.value | _coerce_value($current_spec[$parsed.key].type)) |
      .args |= .[$parsed.consume:]
    ) | _parse_recursive
  end;

# The main entry point function now just calls the recursive helper.
def parse_args:
  _parse_recursive;
