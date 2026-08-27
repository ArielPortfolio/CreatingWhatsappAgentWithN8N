Project purpose:
----------------
Create an AI-backed personal assistant that is available through WhatsApp chat.

High-level features of the assistant:
-------------------------------------
1) The agent acts as my personal assistant and has sensitive access to my personal systems, such as Gmail, Google Drive, and Calendar. Personal profile data is limited to: display name, preferred language, timezone, common contacts, and scheduling preferences. Knowledge is persisted as bounded memory (not infinite growth) using summarized conversation state.
2) The agent acts in a discreet manner, communicating only through my WhatsApp number. Shared secret phrase authentication is deferred and out of scope for the first production release.
3) The agent targets 99.5% monthly availability and is independent of my phone, laptop, or any other physical device.

Agent deployment:
-----------------
The workflow containing the agent will first be deployed in n8n Cloud during the free phase. In the near future the workflow will run from a VPS running n8n locally.

System components:
------------------
1) WhatsApp Communication Manager (WCM): Responsible for receiving and sending messages via WhatsApp, then extracting structured data from text and images.
2) AI agent: A stateful agent that maintains conversation context, uses tools to complete tasks, and responds with actionable output.
3) Supervisor layer: Deferred and out of scope for the first production release.
4) Agent tools:
4.1) Gmail accessor
4.2) Google Drive accessor
4.3) Google Calendar accessor
4.4) Internet search tool (default provider: Brave Search API with safe-search enabled and daily query cap)

System files:
-------------
1) User rules and guidelines: Rulebook for the agent behavior and operating constraints.
2) Agent log file: Execution logs maintained by the workflow for troubleshooting and operational visibility.

Main flows:
-----------
1) Add meeting to calendar:
    - The user sends a WhatsApp message asking to create a meeting.
    - The request should contain:
        - Date and time (default timezone: Asia/Jerusalem when no timezone is provided)
        - Meeting title
        - Location (optional)
        - Contact (optional)
    - The agent receives the prompt through the WCM and invokes the Google Calendar tool using the appropriate API.
    - The agent returns the result to the WCM.
    - The WCM sends the final response back to the user on WhatsApp.

Scope boundaries:
-----------------
In scope:
- Handling whatsapp messages
- Forwarding the message content as prompt for the agent
- Contextful agent which is able to access the tools listed in this doc
- The tools mentioned are implemented

Out of scope:
- Shared secret phrase
- Formal compliance-grade data retention governance
- Customized user-facing error message catalog
- Advanced automated logging redaction

Current implementation status:
------------------------------
1) Meta webhook verification (GET challenge): Implemented.
2) WhatsApp event ingestion (POST webhook): Implemented.
3) Basic message reply from workflow: Implemented.
4) Model response generation: Planned. Default model is Gemini 2.5 Flash, but this is configurable. Prompt policy: pass the user message to the selected model as-is (no post-processing layer).
5) Gmail/Drive/Calendar tool actions from the agent: Planned. Access policy: full access for each tool.
6) Supervisor policy enforcement: Deferred (out of scope for first production release).
7) Persistent memory strategy: Planned. Use n8n Memory node keyed by sender WhatsApp ID; default memory window is 20 turns, configurable via settings.

Security baseline:
------------------
1) Allowed sender phone numbers: Any number allowed by Meta configuration for the connected WhatsApp setup. Group chats are not allowed.
2) Shared secret phrase flow (when required): Deferred (out of scope for first production release).
3) Credential storage and rotation policy: Secrets are stored in n8n Credentials (encrypted at rest). Access is restricted to workspace owner/admin users. No fixed rotation cadence is enforced; credentials are rotated manually when the owner decides, or immediately after suspected exposure.
4) Access-control rules for tools: Full access for all enabled tools in the first production release.
5) Logging redaction rules for sensitive data: Baseline masking applies to tokens, authorization headers, and secret values. Full redaction framework is deferred.

Data policy:
------------
1) Data categories collected: WhatsApp message metadata (sender ID, timestamp), message content, tool call inputs/outputs required for task completion, workflow execution status, and memory summaries.
2) Data storage location(s): n8n Cloud execution database and n8n memory storage backend for this workflow. No additional external data store in first release.
3) Data retention period: No automatic retention limit is applied to data the owner explicitly chooses to save in storage. Retention policy is owner-defined and applied only when explicitly configured.
4) Deletion/reset process: Deferred (out of scope for first production release).
5) PII handling policy: Data minimization by default; only required PII is stored. Secrets are never stored in plain text. Sensitive identifiers should be masked in logs where feasible.

Failure behavior:
-----------------
1) Webhook downtime behavior: Minimal mode for first release. No dedicated external uptime service is required. Operational checks rely on n8n execution failures and manual review.
2) Upstream API failure fallback (Meta/Google): Retry transient failures, then return a generic temporary-failure response and log the incident.
3) Retry strategy (count, interval, backoff): 3 attempts with exponential backoff (5s, 20s, 60s) plus jitter. Use message/event IDs for idempotency checks when available.
4) User-facing error response format: Deferred (out of scope for first production release).
5) Alerting and incident handling: Minimal mode for first release. Alerts are sent to owner email for repeated failures and to owner WhatsApp when monthly cost threshold is reached.

Operational plan:
-----------------
1) n8n Cloud to VPS migration plan: Migration is planned for the future and will be initiated manually by the owner. Timing and reasons are owner-decided.
2) Backup and restore strategy: Deferred (out of scope for first production release).
3) Monitoring dashboards and alert channels: Minimal mode for first release. Use n8n execution view for monitoring and owner email for failure alerts.
4) Monthly cost guardrails: Define an owner-configured monthly cost limit. When the limit is reached, send an alert message to the owner on WhatsApp.

Default assumptions adopted:
----------------------------
1) Personal profile scope is bounded to assistant-relevant preferences and contact/scheduling context.
2) Memory is bounded and summarized (20-turn window by default), not unbounded raw transcript growth.
3) Availability target is 99.5% monthly.
4) Timezone default is Asia/Jerusalem when user input is ambiguous.
5) Internet search defaults to Brave Search API with safe-search and a daily cap.