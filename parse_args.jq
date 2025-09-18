# parse_args.jq - A functional argument parsing pipeline in jq.
#
# Implements a two-stage parsing model (tokenize, then associate) for robustness.
# Reads a "job ticket" JSON object: {"spec": {...}, "args": [...]}
# Outputs the final, parsed JSON object { "key": "value", ... }
# Or, for --help, outputs: { "is_help": true, "message": "..." }

# --- Helper Functions ---

# (Util) A generic type-checking function.
def is_type(type_string):
  if type_string == "string" then type == "string"
  elif type_string == "number" then type == "number"
  elif type_string == "boolean" then type == "boolean"
  elif type_string == "json" then (type == "object" or type == "array")
  elif type_string == "path" then type == "string"
  else false end;

# (Step 1) Generates the help text object for the wrapper to handle.
def generate_help_text($metadata; $spec):
  {
    "is_help": true,
    "message": (
      "\($metadata.description // "")\n\nUsage: [options]\n\nOptions:\n" +
      ($spec | to_entries | map("  --\(.key | gsub("_"; "-"))\t\(.value.description // "")") | .[] | "\(.|tostring)\n")
    )
  };

# (Step 2) Extracts metadata keys into a new object.
def extract_metadata:
  with_entries(select(.key | startswith("_"))) | with_entries(.key |= ltrimstr("_"));

# (Step 3) Removes metadata keys from the spec.
def clean_spec:
  with_entries(select(.key | startswith("_") | not));

# (Step 4) Validates that default values in the spec match their declared types.
def validate_spec_defaults:
  reduce (to_entries[] | select(.value.default != null)) as $entry (.;
    if (($entry.value.default | is_type($entry.value.type)) | not) then
      error("Spec Error: Default for \($entry.key) must be of type \($entry.value.type), but got \($entry.value.default | type).")
    else . end
  );

# (Step 5) Tokenizes arguments, splitting only on the first "=" of keys.
def tokenize_args:
  map(
    if type == "string" and startswith("--") and contains("=") then
      # Find the index of the first "="
      index("=") as $i |
      # Slice the string into a key/value pair at that index
      [.[0:$i], .[$i+1:]]
    else . end
  ) | flatten;

# (Step 6) Associates keys with values, handling booleans in a spec-aware way.
def get_boolean_keys($spec):
  $spec | keys_unsorted | map(select($spec[.].type == "boolean"));

def _associate_recursive($booleans):
  if length == 0 then []
  else
    .[0] as $head | .[1:] as $tail |
    if ($head | startswith("--") | not) then
      error("Argument parsing error: unexpected value '\($head)'.")
    else
      ($head | ltrimstr("--") | gsub("-"; "_")) as $key |
      # Case 1: The flag is at the end, OR the next token is also a flag.
      if ($tail | length == 0) or ($tail[0] | startswith("--")) then
        # Check if this flag is a known boolean.
        if ($booleans | index($key)) then
          [$head, "true"] + ($tail | _associate_recursive($booleans))
        else
          error("Argument \($head) requires a value.")
        end
      # Case 2: The next token is a value.
      else
        [$head, $tail[0]] + ($tail[1:] | _associate_recursive($booleans))
      end
    end
  end;

def associate_keys_with_values($spec):
  get_boolean_keys($spec) as $booleans |
  _associate_recursive($booleans);

# (Step 7) Checks for duplicate keys.
def pairs:
  if length == 0 then [] else [.[0:2]] + (.[2:] | pairs) end;
def check_for_duplicates:
  (pairs | group_by(.[0]) | map(select(length > 1)) | .[0]?) as $first_dup_group |
  if $first_dup_group then
    error("Duplicate argument provided: \($first_dup_group[0][0])")
  else . end;

# (Step 8) Reads from stdin if a single "-" value is present.
def handle_stdin:
  # Count how many times "-" appears as a value.
  ([.[] | select(. == "-")] | length) as $dash_count |
  if $dash_count > 1 then
    error("Cannot read from stdin for more than one argument.")
  elif $dash_count == 1 then
    # If exactly one, replace it with the next entity from the input stream.
    map(if . == "-" then input else . end)
  else
    # Otherwise, return the list unchanged.
    .
  end;

# (Step 9) Normalizes keys by stripping "--" and converting to snake_case.
def normalize_keys:
  reduce range(0; length) as $i (.;
    if $i % 2 == 0 then .[$i] |= (ltrimstr("--") | gsub("-"; "_")) else . end
  );

def objectify:
  # First, save the input array to a variable.
  . as $list |
  if ($list | length) % 2 != 0 then
    error("Cannot objectify list with odd number of elements.")
  else
    reduce range(0; ($list|length); 2) as $i ({};
      # Use the saved variable for indexing, not "."
      . + { ($list[$i]): $list[$i+1] }
    )
  end;

# (Steps 10-13) Builds the final rich object from the flat list and spec,
# with debug messages to trace the data transformation.
def build_and_validate($spec):
  # Step 10a: Convert flat list into an object.
  debug("starting build_and_validate", .) |
  (
    objectify
    | debug("--- 1. User args converted to object ---", .)
  ) as $args |

  # Check for unknown keys by comparing the arg keys and spec keys.
  ( ($args | keys_unsorted) - ($spec | keys_unsorted) | .[0]? ) as $unknown_key |
  if $unknown_key then
    # Use debug to show which key was identified as unknown before exiting.
    debug("!!! Found unknown key: \($unknown_key)", .) |
    error("Unknown option: --\($unknown_key | gsub("_"; "-"))")
  else
    # Step 10b: Start with the spec, then fold in values from the args.
    (
      reduce ($args | keys[]) as $key ($spec;
        .[$key].value = $args[$key]
      )
      | debug("--- 2. Spec after folding in user values ---", .)
    )
    # Steps 11 & 12: Apply defaults, coerce, and validate types in a single pass.
    | (
        with_entries(
          # Apply default if needed
          (if .value.value == null and .value.default != null then
            .value.value = .value.default
          else . end) |

          debug("After applying default (if needed) for key \(.key)", .) |

          # Coerce and validate the final value, if one exists
          (.value.value as $val |
            if $val != null then
              # Coerce non-string types from JSON
              ($val | if .value.type != "string" and .value.type != "path" then (try fromjson catch .) else . end) as $coerced |
              # Validate the final type
              if ($coerced | is_type(.value.type) | not) then
                error("Type Error for --\(.key): Expected \(.value.type) but got `\($coerced | tojson)`. (\($coerced | type))")
              # If valid, update the entry with the potentially coerced value
              else .value.value = $coerced
              end
            else . end)
        )
        | debug("--- 3. Spec after applying defaults and validating types ---", .)
      )
    # Step 13: Check for required args using a more declarative pattern.
    | . as $final |
      (
        $final | keys[]
        | select($final[.].required and $final[.].value == null)
        | first
      ) as $missing_key |
      if $missing_key then
        debug("!!! Found missing required key: \($missing_key)", .) |
        error("Required argument missing: --\($missing_key | gsub("_"; "-"))")
      else
        $final
      end
  end;

# --- Main Pipeline ---

# The $ticket variable is provided by the --argjson flag in the wrapper.
$ticket as $ticket |

# Step 1: Handle help flag as a special early-exit case.
if ($ticket.args | index("--help")) or ($ticket.args | index("--help=true")) then
  generate_help_text(($ticket.spec | extract_metadata); ($ticket.spec | clean_spec))
else
  # Prepare specs
  ($ticket.spec | extract_metadata) as $metadata |
  ($ticket.spec | clean_spec | validate_spec_defaults) as $clean_spec |
  # Start the argument processing pipeline
  $ticket.args
  | debug("before tokenize_args", .)
  | tokenize_args
  | debug("before associate_keys_with_values", .)
  | associate_keys_with_values($clean_spec)
  | debug("before check_for_duplicates", .)
  | check_for_duplicates
  | debug("before handle_stdin", .)
  | handle_stdin
  | debug("before normalize_keys", .)
  | normalize_keys
  | debug("before build_and_validate", .)
  | build_and_validate($clean_spec)
  # Finally, flatten the rich spec object to a simple {key: value} map for output
  | debug("before flattening rich spec object", .)
  | with_entries(select(.value | has("value"))) | with_entries(.value = .value.value)
end
