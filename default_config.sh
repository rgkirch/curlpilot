# User-configurable settings for curlpilot.sh

# Color for summarization messages (ANSI escape codes)
# Example: Yellow (0;33), Cyan (0;36), Green (0;32), Red (0;31)
# Format: "\033[<style>;<color>m"
# Reset: "\033[0m"
SUMMARIZE_COLOR="\033[0;33m" # Default to Yellow

# LLM Token Limits and Character Conversion
LLM_TOKEN_LIMIT=8000
CHARS_PER_TOKEN=4

# Configuration for history and main config directory
CONFIG_DIR="$HOME/.config/curlpilot"
HISTORY_FILE="$CONFIG_DIR/convo_history.txt"

# Summarization Prompt Levels
# Users can choose the aggressiveness of summarization.
# Options: CONCISE, NORMAL, DETAILED
SUMMARIZATION_LEVEL="NORMAL"

# Prompt for concise summarization
SUMMARIZATION_PROMPT_CONCISE=$(cat <<'EOF'
You are the assistant and this is your conversation history with the user but it has grown too long. Rewrite the following conversation to about 40% of its current size. Summarize the conversation history while preserving clear delineation of User Assistant speaker rolls interaction in only the most recent messages. Use simple language and remove superfluous language while still preserving all detail.
EOF
)

# Prompt for normal summarization
SUMMARIZATION_PROMPT_NORMAL=""

# Prompt for detailed summarization
SUMMARIZATION_PROMPT_DETAILED=$(cat <<'EOF'
You are the assistant and this is your conversation history with the user. Rewrite the following conversation to about 80% of its current size while preserving clear delineation of User Assistant speaker rolls interaction. Use simple language and remove superfluous language while still preserving all detail.
EOF
)

PROMPT_EXTRACT_PERSONA_AND_TASK_DIRECTIVES=cat <<'EOF'
You are a highly advanced AI that deconstructs user requests. Your function is to parse the user's input and sort every piece of information into one of two categories: **Persistent Persona Directives** or the **Current Task Context**.

Your analysis must be guided by the following logic:

**1. The Persistence Test:**
For every piece of information, ask the primary question:
> **"Does this instruction or fact apply to our entire conversation from now on, or is it specifically for completing the current, immediate task?"**

**2. Categorization Rules:**

* **Persistent Persona Directives:** If the information passes the persistence test (it's for the entire conversation), extract it here. This category is *only* for timeless, assistant-scoped rules that define my persona and communication style.
    * *Examples to Extract:* "Always be concise," "From now on, call me 'Lead Developer'," "Never use emojis."

* **Current Task Context:** If the information is for the immediate task, extract it here. This category is a comprehensive container for *everything* needed to successfully complete the current request. This includes:
    * **Objective:** The main goal of the task (e.g., "Draft a project proposal").
    * **Facts:** Key pieces of data (e.g., "The target audience is casual gamers").
    * **Constraints & Requirements:** Non-negotiable rules and ephemeral instructions for the task (e.g., "Windows compatibility is a hard requirement," "The summary must be in a bulleted list," "Keep the email under 200 words").

**3. Output Format:**
Your final output must be a valid JSON object with two top-level keys: `persistent_persona_directives` and `current_task_context`, each of which must be a list of strings.

**User Request to Analyze:**

[Insert user's text here]

EOF

PROMPT_EXTRACT_PERSONA_DIRECTIVES=cat <<'EOF'
You are a highly specialized AI assistant. Your sole function is to analyze user requests to identify and extract **persistent, assistant-scoped behavioral directives**. These are timeless rules about how I, your user, want you to behave for the entire duration of our interaction.

Your primary goal is to filter out for removal all ephemeral, task-specific instructions.

From the user's text below, you must perform the following analysis:

**1. Identify all potential instructions.**
Look for any statement that tells the assistant what to do, how to do it, or what style to use.

**2. Apply the Persistence Litmus Test to each instruction.**
For each instruction you find, ask this critical question:
> **"Is the user telling me how to complete the CURRENT task, or are they telling me how they want me to behave from now on?"**

* If it's about the **current task** (e.g., the content of a specific email, the format of a single report), it is **ephemeral**. You must IGNORE it.
* If it's about the **assistant's general behavior** (e.g., your tone, personality, response format for all future messages), it is **persistent**. You must EXTRACT it.

* **Persistent Directives (The Target):** These are the assistant-scoped rules that pass the litmus test. They are instructions for the assistant's persona.
    * *Examples:* "Always speak in a formal tone," "From now on, use bullet points for lists," "Never use emojis," "Refer to me as 'Captain'."

* **Ephemeral Directives (To Be Ignored):** These are task-scoped instructions that fail the litmus test.
    * *Examples:* "Write an email for me," "Make the email sound friendly," "Summarize the attached document," "Keep the summary under 200 words."

**Output Format:**
Your final output must be a valid JSON list of the extracted strings that passed the litmus test. If no persistent directives are found, return an empty list.

**User Request to Analyze:**

[Insert user's text here]

EOF

PROMPT_RECONCILE_PERSONA_DIRECTIVES=$(cat <<'EOF'
You are a logical AI assistant specializing in consolidating and reconciling behavioral directives. Your task is to take an existing list of directives and a new list of recently extracted directives and merge them into a single, clean, consistent, and up-to-date set of rules.

You will be given two JSON lists:
1.  `existing_directives`: The master list of rules currently in effect.
2.  `newly_extracted_directives`: The list of directives identified from the user's most recent message.

Your goal is to produce a single `reconciled_directives` list by following these rules in order:

**1. Combine and De-duplicate:**
Start by combining the two lists. Remove any exact, case-sensitive duplicates.

**2. Identify Semantic Duplicates:**
Analyze the combined list for directives that are semantically identical, even if worded differently (e.g., "Be brief" and "Keep your answers short"). If you find semantic duplicates, you must discard the older one from the `existing_directives` list and keep the newer, potentially more refined version from the `newly_extracted_directives` list.

**3. Resolve Conflicts and Updates (The Precedence Rule):**
Scan the list for directives that contradict each other (e.g., "Never use emojis" vs. "Always use emojis") or update a previous rule (e.g., "Call me Captain" vs. "Call me Admiral").
* **The newest directive always wins.** If you find a conflict, the directive from the `newly_extracted_directives` list takes precedence. The older, conflicting directive from the `existing_directives` list MUST be discarded.

**4. Final Review:**
Produce a final, clean list of directives.

**Output Format:**
Your final output must be a single, valid JSON object with one key: `reconciled_directives`, which contains the final list of strings.

**Input for Reconciliation:**
```json
{
  "existing_directives": [
    // Insert the existing JSON list here
  ],
  "newly_extracted_directives": [
    // Insert the new JSON list here
  ]
}
EOF
)

# persistent_persona_directives are the Constitution. They are the enduring, high-level laws that govern the assistant's behavior. Amending the Constitution is a deliberate process of replacing or adding articles (e.g., "Call me Admiral" replaces "Call me Captain"). The reconciliation prompt we built is perfect for this.
# current_task_context is the Mission Briefing. It's a temporary, detailed set of instructions and data for a single, specific operation. As the mission evolves over several messages, you don't "reconcile" the old briefing with the new one; you accumulate information and update specific parameters within the current briefing.

# if a user adds a new fact, you don't want to risk it being misinterpreted as a "conflict" with an old fact. You simply want to add it to the list of facts

PROMPT_RECONCILE_CONTEXT=$(set <<'EOF'
You are a state management AI. Your job is to maintain an accurate understanding of the user's current task by updating a "Task Context" object based on their latest message.

You will be given two inputs:
1.  `existing_task_context`: The JSON object representing our understanding of the task before the latest message.
2.  `new_user_message`: The user's most recent message.

Your task is to analyze the `new_user_message` and produce a single, `updated_task_context` JSON object by following these rules:

1.  **Carry Over:** All information from the `existing_task_context` should be carried over unless explicitly changed.
2.  **Accumulate Information:** If the new message provides additional facts or constraints, add them to the appropriate lists (`facts`, `constraints_and_requirements`).
3.  **Apply Updates:** If the new message corrects or changes a piece of information already in the context (e.g., changes a budget, a name, or a requirement), the new information from the latest message is considered the correct version and must replace the old information.
4.  **Maintain Structure:** The final output must be the complete, updated task context object, maintaining its original structure.

**Inputs:**
```json
{
  "existing_task_context": {
    // Insert the existing JSON object here
  },
  "new_user_message": "..." // Insert the raw text of the user's new message here
}
EOF
)
