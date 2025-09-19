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

# --- Stage 1: Spec Preparation ---

# Generates the help text object.
def generate_help_text($metadata; $spec):
  {
    "is_help": true,
    "message": (
      "\($metadata.description // "")\n\nUsage: [options]\n\nOptions:\n" +
      ($spec | to_entries | map("  --\(.key | gsub("_"; "-"))\t\(.value.description // "")") | .[] | "\(.|tostring)\n")
    )
  };

# Extracts metadata keys (starting with "_") into a new object.
def extract_metadata:
  with_entries(select(.key | startswith("_"))) | with_entries(.key |= ltrimstr("_"));

# Removes metadata keys from the spec.
def clean_spec:
  with_entries(select(.key | startswith("_") | not));

# Validates that default values in the spec match their declared types.
def validate_spec_defaults:
  reduce (to_entries[] | select(.value.default != null)) as $entry (.;
    if (($entry.value.default | is_type($entry.value.type)) | not) then
      error("Spec Error: Default for \($entry.key) must be of type \($entry.value.type), but got \($entry.value.default | type).")
    else . end
  );

# --- Stage 2: Raw Argument Processing ---

# Tokenizes arguments, splitting only on the first "=" of keys.
def tokenize_args:
  map(
    if type == "string" and startswith("--") and contains("=") then
      index("=") as $i | [.[0:$i], .[$i+1:]]
    else . end
  ) | flatten;

# Associates keys with values, handling booleans in a spec-aware way.
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
      if ($tail | length == 0) or ($tail[0] | startswith("--")) then
        if ($booleans | index($key)) then
          [$head, "true"] + ($tail | _associate_recursive($booleans))
        else
          error("Argument \($head) requires a value.")
        end
      else
        [$head, $tail[0]] + ($tail[1:] | _associate_recursive($booleans))
      end
    end
  end;

def associate_keys_with_values($spec):
  get_boolean_keys($spec) as $booleans |
  _associate_recursive($booleans);

# Groups a flat list into pairs and checks for duplicate keys.
def pairs:
  if length == 0 then [] else [.[0:2]] + (.[2:] | pairs) end;
def check_for_duplicates:
  (pairs | group_by(.[0]) | map(select(length > 1)) | .[0]?) as $first_dup_group |
  if $first_dup_group then
    error("Duplicate argument provided: \($first_dup_group[0][0])")
  else . end;

# Reads from stdin if a single "-" value is present.
def handle_stdin:
  ([.[] | select(. == "-")] | length) as $dash_count |
  if $dash_count > 1 then
    error("Cannot read from stdin for more than one argument.")
  elif $dash_count == 1 then
    map(if . == "-" then input else . end)
  else
    .
  end;

# Normalizes keys by stripping "--" and converting to snake_case.
def normalize_keys:
  reduce range(0; length) as $i (.;
    if $i % 2 == 0 then .[$i] |= (ltrimstr("--") | gsub("-"; "_")) else . end
  );

# Converts a flat [key, value, key, value] list to a JSON object.
def objectify:
  . as $list |
  if ($list | length) % 2 != 0 then
    error("Cannot objectify list with odd number of elements.")
  else
    reduce range(0; ($list|length); 2) as $i ({};
      . + { ($list[$i]): $list[$i+1] }
    )
  end;

# --- Stage 3: Building the Final Object (Refactored) ---

# (Step 3.1) Checks for unknown arguments against the spec.
def _check_for_unknown_args($spec):
  ( (keys_unsorted) - ($spec | keys_unsorted) | .[0]? ) as $unknown_key |
  if $unknown_key then
    error("Unknown option: --\($unknown_key | gsub("_"; "-"))")
  else
    . # Pass through on success
  end;

# (Step 3.2) Merges user-provided values into the spec object.
def _merge_args_into_spec($user_args):
  reduce ($user_args | keys[]) as $key (.;
    .[$key].value = $user_args[$key]
  );

# (Step 3.3) Applies default values where no user value was provided.
def _apply_defaults:
  with_entries(
    if .value.value == null and .value.default != null then
      .value.value = .value.default
    else . end
  );

# (Step 3.4) Coerces strings to their proper types and validates them.
def _coerce_and_validate_types:
  debug("Start _coerce_and_validate_types. Input object:", .) |
  with_entries(
    debug("--- Processing entry key: \(.key). Initial state:", .) |

    if .value.value != null then
      # Coerce the value from a string to its proper JSON type if needed.
      (
        debug("Value is not null. Attempting coercion. Expected type: \(.value.type), Current value: \(.value.value | tojson)") |
        if .value.type != "string" and .value.type != "path" then
          (
            debug("Type is not string/path. Calling 'fromjson'.") |
            # Use try/catch to handle strings that aren't valid JSON.
            .value.value | try fromjson catch (debug("`fromjson` failed, using original value."), .)
          )
        else
          (
            debug("Type is string or path. No coercion needed.") |
            .value.value
          )
        end
      ) as $coerced |
      debug("Coerced value is: \($coerced | tojson). Actual type is: \($coerced | type)") |

      # Validate that the coerced value has the expected type.
      debug("Starting type validation.") |
      (.value.type) as $expected_type |
      ($coerced | is_type($expected_type)) as $is_valid_type |
      debug("Validation check: is_type(\($expected_type)) returned: \($is_valid_type)") |

      if ($is_valid_type | not) then
        (
          debug("Type validation FAILED. Preparing to throw error.") |
          error("Type Error for --\(.key): Expected \($expected_type) but got `\($coerced | tojson)`. (\($coerced | type))")
        )
      else
        (
          debug("Type validation PASSED. Updating entry.") |
          # If valid, update the entry with the correctly typed value.
          (.value.value = $coerced) |
          debug("Entry updated. Final state for this entry:", .)
        )
      end
    else
      # If the initial value is null, there's nothing to do.
      (
        debug(".value.value is null. Skipping coercion and validation for this entry.") |
        . # Return entry unchanged
      )
    end
  ) |
  debug("End _coerce_and_validate_types. Final object:", .)
  ;

# (Step 3.5) Checks for any missing required arguments.
def _check_for_required_args:
  . as $spec |
  [
    keys[]
    | select($spec[.].required and ($spec[.].value | (. == null or . == "")))
  ] as $missing_keys |

  if ($missing_keys | length > 0) then
    # Construct an error message with all missing keys
    ($missing_keys | map("--" + gsub("_"; "-")) | join(", ")) as $errmsg |
    error("Required arguments missing: \($errmsg)")
  else
    . # Pass through on success
  end;

# --- Main Pipeline ---

$ticket as $ticket |

if ($ticket.args | index("--help")) or ($ticket.args | index("--help=true")) then
  debug("Help requested. Generating help text.") |
  generate_help_text(($ticket.spec | extract_metadata); ($ticket.spec | clean_spec))
else
  # Prepare specs
  ($ticket.spec | extract_metadata) as $metadata |
  debug("Extracted metadata: \($metadata)") |
  ($ticket.spec | clean_spec | validate_spec_defaults) as $clean_spec |
  debug("Cleaned and validated spec: \($clean_spec)") |

  # Process raw args into a user args object
  (
    $ticket.args
    | debug("--- 0a. Raw args ---", .)
    | tokenize_args
    | debug("--- 0b. After tokenize_args ---", .)
    | associate_keys_with_values($clean_spec)
    | debug("--- 0c. After associate_keys_with_values ---", .)
    | check_for_duplicates
    | debug("--- 0d. After check_for_duplicates ---", .)
    | handle_stdin
    | debug("--- 0e. After handle_stdin ---", .)
    | normalize_keys
    | debug("--- 0f. After normalize_keys ---", .)
    | objectify
  ) as $user_args |
  debug("--- 1. User args processed and objectified ---", $user_args) |

  # Start the validation and building pipeline
  $user_args
  | _check_for_unknown_args($clean_spec)
  | debug("--- 2. Passed unknown arg check ---", .)
  | . as $validated_user_args
  | $clean_spec
  | debug("--- 3. Starting with clean spec ---", .)
  | _merge_args_into_spec($validated_user_args)
  | debug("--- 4. Spec after merging user args ---", .)
  | _apply_defaults
  | debug("--- 5. Spec after applying defaults ---", .)
  | _coerce_and_validate_types
  | debug("--- 6. Spec after coercion and validation ---", .)
  | _check_for_required_args
  | debug("--- 7. Spec after checking for required args ---", .)
  # Finally, flatten the rich spec object
  | with_entries(select(.value | has("value"))) | with_entries(.value = .value.value)
  | debug("--- 8. Final flattened object ---", .)
end
