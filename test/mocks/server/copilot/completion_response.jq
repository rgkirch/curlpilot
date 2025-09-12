# 0. Define static variables needed for the recipe
{
  "hate": { "filtered": false, "severity": "safe" },
  "self_harm": { "filtered": false, "severity": "safe" },
  "sexual": { "filtered": false, "severity": "safe" },
  "violence": { "filtered": false, "severity": "safe" }
} as $filter_results |

# 1. Define final values from input with defaults
(
  .message_content // "This is a mock Copilot response."
) as $content |
(
  .prompt_tokens // 999
) as $prompt_tokens |
(
  .completion_tokens // ($content | length / 4 | floor)
) as $completion_tokens |

# 2. Perform calculations
($prompt_tokens + $completion_tokens) as $total_tokens |
"chatcmpl-\(now | tostring | sub("\\."; ""))" as $id |

# 3. Construct the output object
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "content_filter_results": $filter_results,
      "message": {
        "content": $content,
        "padding": "abcdefghijklmnopqrstuvwxyz012",
        "role": "assistant"
      }
    }
  ],
  "id": $id,
  "usage": {
    "completion_tokens": $completion_tokens,
    "completion_tokens_details": { "accepted_prediction_tokens": 0, "rejected_prediction_tokens": 0 },
    "prompt_tokens": $prompt_tokens,
    "prompt_tokens_details": { "cached_tokens": 0 },
    "total_tokens": $total_tokens
  },
  "model": "gpt-4.1-2025-04-14",
  "prompt_filter_results": [
    {
      "content_filter_results": $filter_results,
      "prompt_index": 0
    }
  ],
  "system_fingerprint": "fp_c79ab13e31"
}
