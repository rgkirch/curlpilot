# Helper to parse a single argument token like "--key=value" or "--key".
# It uses the `capture` function with a named group regular expression
# to robustly separate the key from an optional value.
# Output: {key: "...", value: "..." | null}
def _parse_cli_token:
  sub("^--"; "")
  | capture("^(?<key>[^=]+)(=(?<value>.*))?$")
  | .key |= gsub("-"; "_");

# Helper to convert a string value to the type defined in the spec.
# It handles a special case for "--messages=-" where a value of "-"
# for a JSON type is passed through without being parsed.
def _coerce_value(type):
  if type == "boolean" then toboolean
  elif type == "json" and . != "-" then fromjson
  else . # string or other types
  end;

# Main function to parse arguments based on a spec.
# It iteratively consumes tokens from the `args` array and folds
# the parsed values into the `spec` object.
def parse_args:
  # The initial state for the loop is the input object itself.
  while(
    .args | length > 0;

    # Deconstruct state for this iteration using variables.
    .args[0] as $current_arg |
    .args[1:] as $remaining_args |
    .spec as $current_spec |

    # 1. Parse the current argument token.
    ($current_arg | _parse_cli_token) as $token |

    # 2. Determine the key, value, and how many arg tokens to consume.
    (
      if $token.value != null then
        # Case: --key=value was found in a single token.
        { key: $token.key, value: $token.value, consume: 1 }
      else
        # Case: --key is a standalone token.
        $current_spec[$token.key] as $spec_entry |
        if ($remaining_args | length > 0) and ($remaining_args[0] | startswith("--") | not) then
          # A value follows the key, so consume two tokens.
          { key: $token.key, value: $remaining_args[0], consume: 2 }
        else
          # It's a boolean flag or a key that will use its default value.
          {
            key: $token.key,
            value: (if $spec_entry.type == "boolean" then "true" else $spec_entry.default end),
            consume: 1
          }
        end
      end
    ) as $parsed |

    # 3. Update the state for the next iteration:
    #    - Add the coerced value to the spec.
    #    - Remove the consumed tokens from the args list.
    .spec[$parsed.key].value = ($parsed.value | _coerce_value($current_spec[$parsed.key].type)) |
    .args |= .[$parsed.consume:]
  ) |
  # 4. Return the final, updated spec object.
  .spec
