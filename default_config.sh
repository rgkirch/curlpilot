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
You are the assistant and this is your conversation history with the user but it has grown too long. Rewrite the following conversation to about 60% of its current size. Summarize the conversation history while preserving clear delineation of User Assistant speaker rolls interaction in only the most recent messages. Use simple language and remove superfluous language while still preserving all detail.
EOF
)

# Prompt for normal summarization
SUMMARIZATION_PROMPT_NORMAL=""

# Prompt for detailed summarization
SUMMARIZATION_PROMPT_DETAILED=$(cat <<'EOF'
You are the assistant and this is your conversation history with the user. Rewrite the following conversation to about 80% of its current size while preserving clear delineation of User Assistant speaker rolls interaction. Use simple language and remove superfluous language while still preserving all detail.
EOF
)

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

# I'll use this on new user messages to provide PROMPT_RECONCILE_PERSONA_DIRECTIVES_WITH_SUPERVISION_SOA and PROMPT_RECONCILE_TASK_CONTEXT_WITH_SUPERVISION_SOA with the first pass of extracted data. Agnostic of SOA or AOS.
PROMPT_EXTRACT_PERSONA_DIRECTIVES_AND_TASK_CONTEXT=$(cat <<'EOF'
You are an expert AI assistant that deconstructs user requests into structured data.

Your function is to parse the user's input and extract every piece of information that falls into either one of these two categories: **Persona Directives** or **Task Context**.

Your analysis must be guided by the following logic:

**1. The Persistence Test:**
For every piece of information, ask the primary question:

> **"Does this instruction or fact apply to our entire conversation from now on, or is it specifically for completing the current, immediate task?"**

* **Persistent Persona Directives:** If the information passes the persistence test (it's for the entire conversation), extract it here. This category is *only* for long-term rules that define the assistant's persona and communication style.

  * *Examples to Extract:* "Always be concise," "From now on, call me 'Lead Developer'," "Never use emojis."

* **Current Task Context:** If the information is for the immediate task, extract it here. This category is a comprehensive container for *everything* needed to successfully complete the current request. This includes:

  * **Objective:** The main goal of the task (e.g., "Draft a project proposal").

  * **Facts:** Key pieces of data (e.g., "The target audience is casual gamers").

  * **Constraints & Requirements:** Non-negotiable rules and **temporary** instructions for the task (e.g., "Windows compatibility is a hard requirement," "The summary must be in a bulleted list," "Keep the email under 200 words").

**2. Handling Ambiguity and Empty Fields:**

* **If a category is empty, use an empty array `[]`. Do not invent information.** For example, a simple request may not contain any persona directives.

* **If an instruction is ambiguous (e.g., "Be brief"), default to placing it in `current_task_context`** unless it contains explicit keywords of persistence like "always," "from now on," or "for all future responses."

**3. Output Format:**
**Your final output must be a single, valid JSON object and nothing else.** Do not include any explanatory text, markdown formatting, or other text outside of the JSON structure.

```jsonschema
{
  "type": "object",
  "properties": {
    "persistent_persona_directives": {
      "type": "array",
      "items": { "type": "string" }
    },
    "current_task_context": {
      "type": "object",
      "properties": {
        "objectives": {
          "type": "array",
          "items": { "type": "string" }
        },
        "facts": {
          "type": "array",
          "items": { "type": "string" }
        },
        "constraints_and_requirements": {
          "type": "array",
          "items": { "type": "string" }
        }
      },
      "required": ["objectives", "facts", "constraints_and_requirements"]
    }
  },
  "required": ["persistent_persona_directives", "current_task_context"]
}
```

**User Request to Analyze:**
%s
EOF
)

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

# I would use this after PROMPT_EXTRACT_PERSONA_DIRECTIVES_AND_TASK_CONTEXT to reconcile the old and new persona directives.
# TODO formal vs professional doesn't seem like the best example
PROMPT_RECONCILE_PERSONA_DIRECTIVES_WITH_SUPERVISION_SOA=$(cat <<'EOF'
You are a master AI logician. Your task is to intelligently update a list of persistent persona directives by reconciling three sources of information.

You will be given three inputs:
1.  `existing_directives`: The master list of rules currently in effect.
2.  `newly_extracted_directives`: A pre-processed list of new rules found in the user's latest message.
3.  `new_user_message`: The original, raw text from the user, which serves as the **ultimate source of truth**.

```jsonschema
{
  "type": "object",
  "properties": {
    "existing_directives": { "type": "array", "items": { "type": "string" } },
    "newly_extracted_directives": { "type": "array", "items": { "type": "string" } },
    "new_user_message": { "type": "string" }
  },
  "required": ["existing_directives", "newly_extracted_directives", "new_user_message"]
}
```

Your goal is to produce a single, definitive list of reconciled directives as a valid JSON array of strings.

## Guiding Principles for Reconciliation

* **Primary Goal:** Your main job is to reconcile the `existing_directives` with the user's intent, as expressed in the `new_user_message`.

* **Use of Inputs:**
    * Treat the `newly_extracted_directives` as a helpful but potentially incomplete summary of the user's new rules.
    * Treat the `new_user_message` as the ultimate **source of truth**. Use it to understand the full context, especially for nuanced instructions that the preliminary extraction might have missed, such as:
        * **Removals:** (e.g., "Forget about...")
        * **Updates:** (e.g., "Actually, change X to Y")
        * **Relative Commands:** (e.g., "Do it like that")

* **Logic:** Apply the principles of **uniqueness**, **refinement** (combining similar ideas), and **precedence** (newest rule wins in a direct conflict) to generate the final list.

## Output Format
Your final output must be a single, valid JSON list of strings representing the reconciled directives.

PROMPT_RECONCILE_PERSONA_DIRECTIVES_WITH_SUPERVISION_SOA_2=$(cat <<'EOF'
You are a master AI logician. Your task is to intelligently update a list of persistent persona directives by reconciling three sources of information.

You will be given three inputs:
1.  `existing_directives`: The master list of rules currently in effect.
2.  `newly_extracted_directives`: A pre-processed list of new rules found in the user's latest message.
3.  `new_user_message`: The original, raw text from the user, which serves as the **ultimate source of truth**.

```jsonschema
{
  "type": "object",
  "properties": {
    "existing_directives": { "type": "array", "items": { "type": "string" } },
    "newly_extracted_directives": { "type": "array", "items": { "type": "string" } },
    "new_user_message": { "type": "string" }
  },
  "required": ["existing_directives", "newly_extracted_directives", "new_user_message"]
}
```

Your goal is to produce a single, definitive list of reconciled directives by applying the following logical principles.

## Guiding Principles for Reconciliation

* **Principle of Truth:** The `new_user_message` is the definitive source of the user's intent. The `newly_extracted_directives` should be treated as a helpful summary, but the raw message is the final authority for resolving any ambiguity or conflict.

* **Principle of Precedence:** Newer instructions supersede older ones. When a directive in the `new_user_message` directly contradicts an `existing_directive`, the old directive must be discarded and replaced by the new one.

* **Principle of Explicit Modification:** Analyze the `new_user_message` for explicit instructions to change the state.
    * **Removals:** Look for commands like "forget," "stop," "don't do that anymore" to identify and remove existing directives.
    * **Refinements:** Look for commands like "instead of X, do Y" or "actually, be more..." to modify an existing directive into its new, updated form.

* **Principle of Synthesis:** The final output list must be a clean synthesis of all valid directives. It must not contain duplicates, redundancies, or conflicting rules.

## Example

**Input:**
```
{
  "existing_directives": ["Be formal", "Use emojis in lists"],
  "newly_extracted_directives": ["Be professional", "Do not use emojis"],
  "new_user_message": "Hey, forget what I said about being formal, I'd prefer you to be professional from now on. And please stop using emojis entirely."
}
```

**Correct Output:**
```
["Be professional", "Do not use emojis"]
```

## Output Format
Your final output must be a single, valid JSON array of strings and nothing else. Do not include explanatory text, markdown formatting, or any text outside of the JSON structure.

```
{
  "type": "array",
  "items": { "type": "string" }
}
```
EOF
)

PROMPT_RECONCILE_TASK_CONTEXT_WITH_SUPERVISION_SOA=$(cat <<'EOF'
You are a master state management AI. Your purpose is to produce the most accurate and up-to-date "Task Context" by synthesizing three sources of information: the existing context, a preliminary analysis of the new message, and the user's raw message itself.

You will be given three inputs:
1.  `existing_task_context`: The JSON object representing the task state before the latest message.
2.  `newly_extracted_context`: A pre-processed JSON object extracted from the new message.
3.  `new_user_message`: The original, raw text from the user.

```jsonschema
{
  "$defs": {
    "taskContext": {
      "type": "object",
      "properties": {
        "objectives": {
          "type": "array",
          "items": { "type": "string" }
        },
        "facts": {
          "type": "array",
          "items": { "type": "string" }
        },
        "constraints_and_requirements": {
          "type": "array",
          "items": { "type": "string" }
        },
        "processing_notes": {
          "type": "array",
          "items": { "type": "string" }
        }
      },
      "required": ["objectives", "facts", "constraints_and_requirements", "processing_notes"]
    }
  }
  "type": "object",
  "properties": {
    "existing_task_context": { "$ref": "#/$defs/taskContext" },
    "newly_extracted_context": { "$ref": "#/$defs/taskContext" },
    "new_user_message": { "type": "string" }
  },
  "required": ["existing_task_context", "newly_extracted_context", "new_user_message"]
}
```

Your goal is to produce a single, definitive `updated_task_context` JSON object.

## Guiding Principles for Reconciliation

* **Primary Goal:** Your main job is to accurately reflect the user's current intent for the task by intelligently merging the provided information.

* **Use of Inputs:**
    * Treat the `newly_extracted_context` as a helpful but potentially incomplete "first pass" analysis. It highlights the most obvious new information.
    * Treat the `new_user_message` as the ultimate **source of truth**. Use it to understand the full context and correct any misinterpretations or omissions from the preliminary extraction, especially for:
        * **Removals:** (e.g., "Actually, we don't need a pool anymore.")
        * **Updates vs. Additions:** (e.g., "The budget is now $6,000," which updates an old fact rather than adding a new one.)
        * **"Yak Shaving":** (e.g., "Before that, we need to...")
        * **Task Completion:** (e.g., "Okay, that's done.")

* **Key-Specific Logic:**
    * **For `objectives` (the task stack):** Use the `new_user_message` to determine if a new prerequisite task has been introduced (add to the front of the list) or if the current task (at the front) has been unambiguously completed (remove from the front).
    * **For `facts` and `constraints_and_requirements`:** Use the `new_user_message` and `existing_task_context` to correctly add, update, or remove items.
    * **For `processing_notes`:** If the user's intent in the `new_user_message` is ambiguous, err on the side of caution (e.g., don't remove an objective) and add a note to this list explaining the ambiguity.

## Output Format
Your final output must be a single, valid JSON object representing the complete and `updated_task_context`.
```jsonschema
{
  "type": "object",
  "properties": {
    "objectives": {
      "type": "array",
      "items": { "type": "string" }
    },
    "facts": {
      "type": "array",
      "items": { "type": "string" }
    },
    "constraints_and_requirements": {
      "type": "array",
      "items": { "type": "string" }
    },
    "processing_notes": {
      "type": "array",
      "items": { "type": "string" }
    }
  },
  "required": ["objectives", "facts", "constraints_and_requirements"]
}
```
EOF
)

# I'm leaning towards not using this in favor of PROMPT_RECONCILE_TASK_CONTEXT_WITH_SUPERVISION_SOA.
PROMPT_RECONCILE_CONTEXT=$(cat <<'EOF'
You are a state management AI. Your purpose is to maintain a complete and accurate understanding of the user's current task by intelligently updating a "Task Context" object based on their latest message. You must account for "yak shaving," where new, prerequisite tasks emerge that must be completed before returning to the main goal.

You will be given two inputs:
1.  `existing_task_context`: The JSON object representing our understanding of the task *before* the latest message.
2.  `new_user_message`: The raw text of the user's most recent message.

```jsonschema
{
  "type": "object",
  "properties": {
    "objectives": {
      "type": "array",
      "items": { "type": "string" }
    },
    "facts": {
      "type": "array",
      "items": { "type": "string" }
    },
    "constraints_and_requirements": {
      "type": "array",
      "items": { "type": "string" }
    },
    "new_user_message": { "type": "string" }
  },
  "required": ["new_user_message"]
}
```

Your goal is to produce a single, `updated_task_context` JSON object. The final object must adhere to the following principles:

## Guiding Principles for Context Updates

### 1. Overall Precedence 🥇
The updated context must always reflect the most current information. If the `new_user_message` contradicts or replaces any existing information, the **new information is the single source of truth**.

### 2. Principle of Cautious Completion and Clarity 🚦
* **Error on the side of caution.** An objective should only be considered complete if the user's message is **clear and unambiguous** about its completion.
* **Communicate Uncertainty.** If you are uncertain about whether the current objective is complete, **you must not remove it**. Instead, add a brief note explaining the ambiguity to the `processing_notes` list.

### 3. Key-Specific Logic 🔑
You must apply specific update logic based on the key within the JSON object:

* **For `objectives` (a list of strings representing a task stack):**
    * **The list is a stack:** Treat this list as a stack of goals. The objective at the front of the list (index 0) is the **most immediate task**.
    * **Adding a Prerequisite (Yak Shaving):** If the new message introduces a sub-task that appears to be a **blocker, dependency, or necessary first step** for the current objective, add this new task to the **front** of the list.
    * **Completing a Task:** If the user **unambiguously confirms** the completion of the current (front of the list) objective, **remove it** to reveal the next task.

* **For `facts` and `constraints_and_requirements` (lists of strings):**
    * **Accumulate** new, non-conflicting items.
    * **Update or Remove** existing items if the user provides a direct correction or cancellation.

## Output Format
Your final output must be a single, valid JSON object containing four top-level keys: `objectives`, `facts`, `constraints_and_requirements`, and `processing_notes` (which is a list of strings).

## Inputs
```json
%s
```
EOF
)

# I think I would only use this to initialize things. After I've done this once, then I need to reconcile, not extract. Also, I'm leaning towards not using this prompt in favor or PROMPT_EXTRACT_PERSONA_DIRECTIVES_AND_TASK_CONTEXT.
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
```jsonschema
{
  "type": "array",
  "items": { "type": "string" }
}
```
**User Request to Analyze:**
%s
EOF


# I'm leaning towards not using this in favor of PROMPT_RECONCILE_PERSONA_DIRECTIVES_WITH_SUPERVISION_SOA.
PROMPT_RECONCILE_PERSONA_DIRECTIVES=$(cat <<'EOF'
You are an AI assistant specializing in consolidating and reconciling behavioral directives.

Your task is to take an existing list of directives and a new list of recently extracted directives and produce a single, clean, consistent, and up-to-date set of rules.

You will be given a single JSON object with two keys:
1.  `existing_directives`: The master list of rules currently in effect.
2.  `newly_extracted_directives`: The list of directives identified from the user's most recent message.

```jsonschema
{
  "type": "object",
  "properties": {
    "existing_directives": {
      "type": "array",
      "items": { "type": "string" }
    },
    "newly_extracted_directives": {
      "type": "array",
      "items": { "type": "string" }
    }
  },
  "required": ["existing_directives", "newly_extracted_directives"]
}
```

Your goal is to produce a single `reconciled_directives` list that adheres to the following principles:

## Guiding Principles for Reconciliation

* **Uniqueness and Refinement:** The final list must not contain duplicate directives, whether they are exact textual matches or just semantically identical.
    * If two directives are related but not contradictory, you must **combine and refine them into a single, more comprehensive directive** that captures the intent of both.
    * For example, `"Use simple language to explain"` and `"Stop using jargon"` should be merged into a refined directive like: **`"Explain topics using simple language, avoiding jargon."`**

* **Conflict Resolution and Precedence:** The final list must be internally consistent.
    * If a directive from the `newly_extracted_directives` list **directly contradicts or clearly updates** a directive from the `existing_directives` list (e.g., `"Call me Captain"` vs. `"Call me Admiral"`), the **newest directive always wins**. The older, conflicting directive must not be included in the final output.

* **Comprehensiveness:** The final list should accurately represent the complete, current set of instructions, including all unique, non-conflicting directives from both input lists, with related items intelligently merged.

## Output Format
Your final output must be a single, valid JSON list of strings representing the reconciled directives.

```jsonschema
{
  "type": "array",
  "items": { "type": "string" }
}
```

## Input for Reconciliation
```json
%s
```
EOF
)
