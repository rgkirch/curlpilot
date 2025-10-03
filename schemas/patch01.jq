# In schemas/patch01.jq

# Recursively walk the schema and transform all instances of `nullable: true`
# into the modern JSON Schema syntax.
walk(
  if type == "object" and .nullable == true then
    (
      # Case 1: The object has an explicit "type" key.
      if has("type") then
        .type |= (if type == "array" then . + ["null"] | unique else [., "null"] end)

      # Case 2: The object uses "anyOf" to define its types.
      # Add a simple {"type": "null"} schema to the list.
      elif has("anyOf") then
        .anyOf += [{"type": "null"}]

      # Case 3: The object uses "oneOf" (for completeness).
      elif has("oneOf") then
        .oneOf += [{"type": "null"}]

      else
        .
      end
    )
    # In all cases where we made a change, delete the old "nullable" key.
    | del(.nullable)
  else
    .
  end
)
