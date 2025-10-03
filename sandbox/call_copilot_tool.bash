#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"
register_dep request client/copilot/request.bash

# JSON payload for the tool call request
JSON_PAYLOAD='{
  "model": "gpt-4.1",
  "messages": [
    {
      "role": "user",
      "content": "Whats the weather like in Boston, MA in Celsius?"
    }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_current_weather",
        "description": "Get the current weather in a given location",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "The city and state, e.g. San Francisco, CA"
            },
            "unit": {
              "type": "string",
              "enum": ["celsius", "fahrenheit"]
            }
          },
          "required": ["location"]
        }
      }
    }
  ]
}'


exec_dep request --body "$JSON_PAYLOAD"
