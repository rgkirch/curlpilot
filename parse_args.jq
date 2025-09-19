# parse_args.jq

# Recursively process the arguments array, updating the spec.
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
          if ($key_name | in($spec) | not) then
            error("Unknown argument: \($arg)")
          else
            if (($tail | length) == 0) or ($tail[0] | startswith("--")) then
              if ($spec[$key_name].type == "boolean") then
                { key: $key_name, value: true, rest: $tail }
              else
                error("Non-boolean argument \($arg) requires a value")
              end
            else
              { key: $key_name, value: $tail[0], rest: ($tail | .[1:]) }
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

# Remove keys that start with an underscore.
def remove_metadata:
  with_entries(select(.key | startswith("_") | not));

# Fill in default values and check for required arguments.
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

# Substitute any value of "-" with data from stdin.
def substitute_stdin_values:
  with_entries(
    if .value.value == "-" then
      .value.value = input
    else
      . # Leave the entry unchanged
    end
  );

# Convert string argument values to their proper types based on the spec.
def coerce_types:
  map_values(
    if .value | type == "string" then
      if .type == "number" then
        .value |= tonumber
      elif .type == "boolean" then
        .value |= toboolean
      elif .type == "json" then
        .value |= fromjson
      else
        .
      end
    else
      .
    end
  );

# Extract the final value from each spec entry to create the final object.
def extract_values:
  map_values(.value);


# --- Main execution flow ---
{spec: $spec, args: $args}
| process_args
| remove_metadata
| ensure_values
| substitute_stdin_values
| coerce_types
| extract_values
