# Notion AI prototype

This fork adds a Notion AI provider backed by Notion's documented Agent Insights endpoint:

```text
GET https://api.notion.com/v1/agents/notion_ai/insights
```

The adapter displays `total_credits_used`, `credit_limit` (when visible), and `runs_completed` for the current billing window. It uses the user's Notion personal access token (PAT) from Codenotch Settings, stored in the macOS login keychain, or `NOTION_API_TOKEN` from the process environment.

## Authentication

Personal-agent insights for `notion_ai` require a personal access token. In Notion's Developer Portal, create a PAT for the workspace and select the **Notion API** capability. An internal connection token cannot read personal-agent insights and receives a 404. A PAT acts as its creator within that workspace, so treat it like a password and do not commit it or paste it into chat. See Notion's [PAT guide](https://developers.notion.com/guides/get-started/personal-access-tokens) and [agent insights reference](https://developers.notion.com/reference/notion-agent-apis/retrieve-agent-insights).

## What this reading means

This endpoint measures premium AI credits. It is not the six-hour or monthly included-usage percentage shown in Notion's **Settings → Notion AI → Usage** dashboard, and it does not report raw tokens by model or by individual message. Notion documents those allowances separately from premium-model credits in its [usage allowance guide](https://www.notion.com/help/manage-your-usage-allowance-for-notion-ai).

If Notion returns `credit_limit: "hidden"` or no limit, the notch shows the number of credits and completed runs without drawing a percentage from an unknown denominator.

## Conversation completion

This prototype does not announce the end of a personal Notion Agent response. Notion's [Agent API quickstart](https://developers.notion.com/guides/notion-agent-apis/quickstart) is for sessions with a Custom Agent; the official [Notion Agents SDK](https://github.com/makenotion/notion-agents-sdk-js) says personal-agent session access is not supported. The current Notion AI chat UI does not provide this provider with a documented lifecycle event.

The existing Codenotch completion watcher can consume a future Notion activity source if Notion exposes one. A Custom Agent session is a separate supported direction, but does not observe the personal “Cubinho” chat in the screenshots.

## Manual validation

1. Create a personal access token in the Notion Developer Portal, choose the workspace, and enable the **Notion API** capability.
2. Open Codenotch Settings, connect **Notion AI**, and paste the token. The provider refreshes after saving.
3. Compare the returned premium-credit reading with Notion's agent-insights response. Do not compare it with the included six-hour/monthly allowance percentages.

For a command-line test, set `NOTION_API_TOKEN` and run the opt-in test:

```sh
CODENOTCH_TEST_NOTION_LIVE=1 make test
```

The normal test suite uses synthetic response fixtures and never needs a token.
