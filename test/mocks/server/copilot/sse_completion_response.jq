# Define static variables needed for the recipe
{
  "hate": { "filtered": false, "severity": "safe" },
  "self_harm": { "filtered": false, "severity": "safe" },
  "sexual": { "filtered": false, "severity": "safe" },
  "violence": { "filtered": false, "severity": "safe" }
} as $filter_results |

# Use provided created/id for the main chunks from the input JSON
.created as $created_ts |
.id as $id |
"gpt-4.1-2025-04-14" as $model |
"fp_c79ab13e31" as $system_fingerprint |

# 1. Initial chunk with prompt filter results.
# This part is special in the golden file, with created=0 and id="", so we hardcode it.
"data: " + ({
  "choices": [],
  "created": 0,
  "id": "",
  "prompt_filter_results": [
    {
      "content_filter_results": $filter_results,
      "prompt_index": 0
    }
  ]
} | tojson) + "\n",

# 2. Role-setting chunk with empty content
"data: " + ({
  "choices": [
    {
      "index": 0,
      "content_filter_offsets": {"check_offset":30,"start_offset":30,"end_offset":64},
      "content_filter_results": $filter_results,
      "delta": {
        "content": "",
        "role": "assistant"
      }
    }
  ],
  "created": $created_ts,
  "id": $id,
  "model": $model,
  "system_fingerprint": $system_fingerprint
} | tojson) + "\n",

# 3. Iterate through message_parts to generate content-only chunks
(.message_parts | .[] |
  "data: " + ({
    "choices": [
      {
        "index": 0,
        "content_filter_offsets": {"check_offset":30,"start_offset":30,"end_offset":64},
        "content_filter_results": $filter_results,
        "delta": {
          "content": .
        }
      }
    ],
    "created": $created_ts,
    "id": $id,
    "model": $model,
    "system_fingerprint": $system_fingerprint
  } | tojson) + "\n"
),

# 4. Final chunk with finish_reason and usage
"data: " + ({
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "content_filter_offsets": {"check_offset":30,"start_offset":30,"end_offset":64},
      "content_filter_results": $filter_results,
      "delta": {"content":null}
    }
  ],
  "created": $created_ts,
  "id": $id,
  "usage": {
    "completion_tokens": (1 + (.message_parts | length)),
    "completion_tokens_details": {"accepted_prediction_tokens":0,"rejected_prediction_tokens":0},
    "prompt_tokens": (.prompt_tokens // 7),
    "prompt_tokens_details": {"cached_tokens":0},
    "total_tokens": ((.prompt_tokens // 7) + 1 + (.message_parts | length))
  },
  "model": $model,
  "system_fingerprint": $system_fingerprint
} | tojson) + "\n",

# 5. End of stream marker
"data: [DONE]\n"
