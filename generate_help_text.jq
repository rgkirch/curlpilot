# generate_help_text.jq - Validates a spec and formats it into a help message.

# Validates the spec, halting with an error if any public argument is
# missing a string 'description'.
def validate_spec($spec):
  (
    $spec
    | to_entries
    | .[]
    | select(.key | startswith("_") | not)
    | if (.value | has("description") | not) or (.value.description | type != "string") then
        error("Argument '\(.key)' in spec is missing a string 'description'.")
      else
        empty
      end
  ),
  $spec
;

# Formats a validated spec into a help message.
def generate_help($spec):
  # Only print the overall description if it exists.
  if $spec | has("_description") then
    $spec._description
  else
    empty
  end,
  "",
  "USAGE:",
  "  script.sh [OPTIONS]",
  "",
  "OPTIONS:",
  # Iterate over the spec entries and format each line.
  ( $spec
    | to_entries
    | .[]
    | select(.key | startswith("_") | not)
    |
      "  --\(.key | gsub("_"; "-"))\t\(.value.description)" +
      (if .value | has("default") then
        " (default: \(.value.default | tojson))"
      else
        ""
      end)
  )
;

# --- Main execution flow ---
validate_spec($spec) | generate_help(.)
