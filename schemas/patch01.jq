# Recursively walk the schema and transform OpenAPI 3.0's `nullable: true`
# into the modern JSON Schema `type: ["...", "null"]` syntax.
walk(
  if type == "object" and .nullable == true and has("type") then
    # If .type is already an array, add "null" to it.
    # Otherwise, create a new array with the original type and "null".
    .type |= (if type == "array" then . + ["null"] | unique else [., "null"] end)
    # Delete the old "nullable" key.
    | del(.nullable)
  else
    # Leave other objects unchanged.
    .
  end
)
