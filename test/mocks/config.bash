# This mock config overrides the API endpoint to point to our local test server.
# The path in the URL ('/chat/completions') is arbitrary for the test but
# reflects a realistic endpoint.
echo '{"api_endpoint": "http://localhost:8080/chat/completions"}'
