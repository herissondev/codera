# Codera

An AI-assisted Phoenix application.

Quick start

1) Install deps and set up the project:
   mix setup

2) Set your AI provider credentials (OpenRouter):
   # Option A: use .env
   cp .env.example .env
   # add your key to .env, then
   source .env

   # Option B: export directly
   export OPENROUTER_API_KEY=your_key_here

3) Start the server:
   mix phx.server

Visit http://localhost:4000

Notes
- Do not hardcode API keys in source code. Use environment variables as shown above.
- For production, set environment variables via your deployment platform.

Learn more
- Phoenix: https://hexdocs.pm/phoenix/overview.html
- LiveView: https://hexdocs.pm/phoenix_live_view
