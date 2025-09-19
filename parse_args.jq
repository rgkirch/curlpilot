# Recursively process the arguments array, updating the spec.
# The state is passed implicitly as the input context, e.g., {spec: {}, args: []}
def process_args:
  if (.args | length) == 0 then
    .spec # Base case: no more args, return the final spec
  else
    .args[0] as $arg |
    .spec as $spec |

    if ($arg | startswith("--") | not) then
      error("Invalid argument (does not start with --): \($arg)")
    else
      (
        # The logic to parse one argument/value pair
        # Case 1: Argument is in --key=value format
        if ($arg | contains("=")) then
          ($arg | capture("^--(?<k>[^=]+)=(?<v>.*)")) as $kv |
          {
            key: ($kv.k | gsub("-"; "_")),
            value: $kv.v,
            rest: (.args | .[1:])
          }
        # Case 2: Argument is --key value or a boolean --key
        else
          .args[1:] as $tail |
          ($arg | sub("^--"; "") | gsub("-"; "_")) as $key_name |

          # Check if the argument is defined in the spec
          if ($key_name | in($spec) | not) then
            error("Unknown argument: \($arg)")
          else
            if (($tail | length == 0) or ($tail[0] | startswith("--"))) then
              # It's a boolean flag or the last argument
              if ($spec[$key_name].type == "boolean") then
                {
                  key: $key_name,
                  value: true,
                  rest: $tail
                }
              else
                error("Non-boolean argument \($arg) requires a value")
              end
            else
              # The next item in the list is the value
              {
                key: $key_name,
                value: $tail[0],
                rest: ($tail | .[1:])
              }
            end
          end
        end
      ) as $parsed |

      # Update the state and recurse
      {
        spec: (.spec | .[$parsed.key].value = $parsed.value),
        args: $parsed.rest
      } | process_args
    end
  end;

# After processing args, check the spec to:
# 1. Fill in default values for any unset items.
# 2. Error out if a required item (one without a default) is missing.
def ensure_values:
  with_entries(
    if (.value | has("value") | not) then
      if (.value | has("default")) then
        .value.value = .value.default
      else
        error("Missing required value for key: \(.key)")
      end
    else
      .
    end
  );

# After ensuring values, substitute any "-" value with data from stdin.
def substitute_stdin_values:
  with_entries(
    if .value.value == "-" then
      # The `input` builtin reads the next JSON value from stdin.
      .value.value = input
    else
      . # Leave the entry unchanged
    end
  );


# --- Main execution flow ---
process_args | ensure_values | substitute_stdin_values
