# generate_help_text.jq - Formats a spec into a help message.

def generate_help($spec):
  # Helper to format a single option line
  def format_option:
    .key as $key |
    .value as $details |
    (
      if $details.default != null then
        "(default: \($details.default | @json))"
      else ""
      end
    ) as $default_text |
    "  --\(($key | gsub("_"; "-")))\t\( $details.description ) \($default_text)";

  # Main formatting logic
  # FIX: Collect all string parts into a single array before joining.
  [
    (
      $spec._description,
      "",
      "USAGE:",
      "  script.sh [OPTIONS]",
      "",
      "OPTIONS:"
    ),
    (
      $spec
      | to_entries
      | map(select(.key | startswith("_") | not))
      | map(format_option)[]
    )
  ] | join("\n");

# --- Main execution flow ---
generate_help($spec)
