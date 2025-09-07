# Contrasting struct of arrays (SOA) vs array of structs (AOS).
# SOA would be {foo: [string], bar: [baz]} while AOS would be [{foo: string, bar: baz}]
# SOA vs AOS is for what the persisted state looks like. Either way, we process the new user string into a struct. That doesn't change.
# Reconciliaton against SOA vs AOS:
# When reconciling the struct extracted from the new user string against the state when the state is SOA:
# You can transpose the two structs and then reconcile pairs. e.g. for two structs of K keys, you would perform K reconciliations of pairs.
# When reconciling the struct extracted from the new user string against the state when the state is AOS:
# You have branching logic.
# On the one hand, you'd pop off the head struct from the AOS state, reconcile the new struct with that struct, and then add the result to the array of structs.
# On the other hand, you don't pop anything and only add the new struct to the array of structs. i.e. add the new struct representing data from the new user message to the array of structs representing the persisted state.

FRAGMENT_PROCESSING_NOTES=$(cat <<'EOF'
## Definition and Mandate for `processing_notes`

**1. Core Definition:**
A `processing_note` is a high-priority system alert. Its existence signifies that the standard, structured data model (`objectives`, `facts`, `constraints`, `directives`, etc.) has failed to capture a critical piece of nuanced information from the user's message. It is a flag for important data that "doesn't fit the mold."

**2. The Mandate:**
The AI's **immediate and primary objective** upon encountering a `processing_note` is to take action to resolve it. This mandate supersedes the user's most recent task. The system's ideal state is an empty `processing_notes` list.

**3. The Resolution Path:**
Resolving a note requires the AI to address the ambiguity directly with the user. The required action is almost always to **pause the user's task and ask a clarifying question.**

**4. The Ultimate Goal:**
The goal of the clarification is to translate the vague, implicit, or emotional information contained in the note into an explicit, actionable piece of data that *can* fit the structured system. This might result in a new directive, a new constraint, or another concrete modification to the system's persistent state, thereby resolving the note.
EOF
)

FRAGMENT_OUTPUT_JSON=$(cat <<'EOF'
**Your final output must be a single, valid JSON object and nothing else.** Do not include any explanatory text, markdown formatting, or other text outside of the JSON structure.
EOF
)

# Use this to extract persona directives and task content from a user message.
source "./extract_persona_directives_and_task_context.sh"
# I would use this after PROMPT_EXTRACT_PERSONA_DIRECTIVES_AND_TASK_CONTEXT to reconcile the old and new persona directives.
source "./reconcile_persona_directives.sh"
source "./soa/reconcile_task_context.sh"
