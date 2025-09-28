# 1. Define final values from the piped-in JSON object

# The main text content.
(
  .text
) as $content |

# The creation time. Uses current time if the input key is null or an empty string.
(
  if .create_time and (.create_time | length > 0) then
    .create_time
  else
    (now | todateiso8601)
  end
) as $create_time |

# The token counts, using defaults from the bash script.
( .prompt_tokens ) as $prompt_tokens |
( .thoughts_tokens ) as $thoughts_tokens |


# 2. Perform calculations
( $content | length / 4 | floor ) as $candidates_tokens |
( $prompt_tokens + $candidates_tokens + $thoughts_tokens ) as $total_tokens |
( "b" + (now | tostring | sub("[^0-9]"; "") | .[2:22]) ) as $response_id |


# 3. Construct the final output object
{
  "response": {
    "candidates": [
      {
        "content": {
          "role": "model",
          "parts": [
            {
              "text": $content
            }
          ]
        },
        "finishReason": "STOP",
        "avgLogprobs": -0.60702006022135413
      }
    ],
    "usageMetadata": {
      "promptTokenCount": $prompt_tokens,
      "candidatesTokenCount": $candidates_tokens,
      "totalTokenCount": $total_tokens,
      "trafficType": "PROVISIONED_THROUGHPUT",
      "promptTokensDetails": [
        {
          "modality": "TEXT",
          "tokenCount": $prompt_tokens
        }
      ],
      "candidatesTokensDetails": [
        {
          "modality": "TEXT",
          "tokenCount": $candidates_tokens
        }
      ],
      "thoughtsTokenCount": $thoughts_tokens
    },
    "modelVersion": "gemini-2.5-flash",
    "createTime": $create_time,
    "responseId": $response_id
  }
}
