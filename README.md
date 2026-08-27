# CreatingWhatsappAgentWithN8N

## Project Purpose
This project builds a personal WhatsApp AI assistant using n8n as the automation layer.

Target capabilities:
- Receive WhatsApp messages via Meta Webhooks
- Process messages through an AI model (planned: Google Gemini 2.5 Flash)
- Use Google tools (planned): Calendar, Gmail, Drive
- Send responses back to WhatsApp users

Current scope completed in this repo:
- Reliable webhook verification with Meta
- Reliable inbound WhatsApp event handling
- Reliable outbound WhatsApp reply flow from n8n

## What Was Done So Far

### 1) Initial verification workflow created
- Built initial workflow to handle Meta webhook verification challenge.
- Verified GET challenge flow and challenge echo response.
- File: My workflow.json

### 2) Production-ready starter workflow created
- Built a new importable workflow that separates verification and events while using the same webhook path.
- File: WhatsApp Agent Starter.workflow.json

Implemented nodes and behavior:
- Meta Verify Webhook (GET, response via Respond to Webhook node)
- Verify Token Valid? (checks hub_mode and hub_verify_token)
- Return Challenge (200, text/plain, returns hub.challenge)
- Reject Invalid Verify (403)
- WhatsApp Events Webhook (POST, responds immediately on receive)
- Has Incoming Message? (guards against non-message events)
- Send WhatsApp Reply (HTTP POST to Graph API messages endpoint)
- Ignore Non-Message Event (no-op branch)

### 3) End-to-end messaging validated
- Production webhook receives Meta events.
- Incoming WhatsApp messages trigger production executions.
- Reply node sends messages back successfully.

### 4) Git repository setup completed
- Local repository initialized in this project folder.
- Remote set to:
  https://github.com/ArielPortfolio/CreatingWhatsappAgentWithN8N.git
- Initial baseline commit pushed to main.

## Required Configuration (Completed)

### n8n configuration
- Workflow must be Active to serve production webhook URL.
- Verify token in Verify Token Valid? node must match Meta webhook verify token.
- Send WhatsApp Reply node uses Bearer Auth credential.
- Credential token must be valid (non-expired).

### Meta WhatsApp configuration
- Webhook callback configured to n8n production URL.
- Webhook field subscription enabled for messages.
- Test phone number configured as sender in API Setup.
- Personal WhatsApp number present in API Setup To recipient list.

### Token configuration
- System User token generated in Meta Business Settings.
- Permissions used:
  - whatsapp_business_messaging
  - whatsapp_business_management
- Token updated in n8n Bearer Auth credential.

## Obstacles Encountered And How They Were Resolved

### Obstacle 1: Test URL vs Production URL confusion
Issue:
- Meta callback failed when workflow was only listening in n8n test mode.

Resolution:
- Kept workflow Active and used production webhook URL for Meta callback.
- Used Execute Workflow only for test-mode troubleshooting.

### Obstacle 2: No visible production executions
Issue:
- It looked like production endpoint had no activity.

Resolution:
- Confirmed real inbound events from Meta and checked production executions.
- Distinguished outbound Postman send calls from inbound user message events.

### Obstacle 3: Access token expired
Issue:
- Error: Authorization failed, access token session expired.

Resolution:
- Generated new System User token.
- Updated n8n Bearer Auth credential and re-tested.

### Obstacle 4: Recipient not in allowed list
Issue:
- Error (#131030) Recipient phone number not in allowed list.

Resolution:
- Used Meta API Setup page.
- Ensured personal phone number is in the To recipient list for test mode.
- Retested using a real incoming message from allowed number.

## Current Working Flow
1. User sends message to Meta test business number.
2. Meta posts event to n8n production webhook.
3. Workflow validates event contains incoming message.
4. Workflow sends reply using Graph API messages endpoint.
5. User receives response in WhatsApp.

## Repository Contents
- Startup.md: Project goal and architecture planning notes.
- My workflow.json: Initial verification-first workflow.
- WhatsApp Agent Starter.workflow.json: Current working starter workflow.
- README.md: This project summary and setup history.

## Current Priority (POC First)
The current project phase is proof-of-concept, not production hardening.

Primary objective now:
- Add AI-powered meaningful replies in WhatsApp.
- Add Google Calendar integration so the assistant can create appointments from chat requests.

## Deferred Hardening Backlog (Do Later)
These are important, but intentionally postponed until after the AI + Calendar POC is working end-to-end:
- Deduplication/idempotency by WhatsApp message ID
- Failure branch + fallback reply + alerting
- Cost guardrails and loop protection
- Backup/recovery runbook

## POC Plan: AI Reply + Calendar Appointment

### Phase 1: Meaningful AI replies
Goal:
- Replace mirror/echo-style behavior with useful assistant responses.

Why:
- Validates real assistant behavior before adding tool usage.

Implementation:
1. Add Gemini model usage in the message path after Extract Message Data.
2. Send user message text to Gemini with a system prompt describing assistant behavior.
3. Map Gemini output text to Send WhatsApp Reply body.

Success criteria:
- Incoming WhatsApp message gets a contextual AI response.

### Phase 2: Calendar read capability
Goal:
- Assistant can answer availability questions using Google Calendar.

Why:
- Confirms Google OAuth and calendar API integration before create-event actions.

Implementation:
1. Configure Google Calendar credential in n8n (OAuth).
2. Add a branch for availability-style requests.
3. Query calendar events in a time window and summarize results in reply.

Success criteria:
- User asks about schedule and receives a correct availability summary.

### Phase 3: Calendar appointment creation from WhatsApp
Goal:
- Assistant can create an event from a natural-language request.

Why:
- This is the core business-value scenario for the POC.

Implementation:
1. Use AI step to extract structured scheduling fields from message:
  - title
  - date
  - start_time
  - end_time (or duration)
  - timezone
2. Validate required fields.
3. If fields are missing, ask a follow-up question in WhatsApp.
4. If fields are complete, call Google Calendar Create Event.
5. Reply confirmation with created event time/details.

Success criteria:
- User sends appointment request in WhatsApp and event is created in Google Calendar.

## Recommended Node-Level Flow (POC)
1. WhatsApp Events Webhook
2. Has Incoming Message?
3. Extract Message Data
4. Intent + entity extraction (AI step)
5. IF branch:
  - calendar_create -> Google Calendar Create Event -> confirmation reply
  - calendar_check -> Google Calendar read/list -> summary reply
  - default_chat -> Gemini reply -> Send WhatsApp Reply

## POC Scope Boundaries
In this phase, keep it simple:
- Single user (you)
- Single calendar
- Text messages only
- Basic timezone assumption (configured once)

## Resume-Quick Checklist
When resuming this project later, start here:
1. Confirm webhook still receives inbound WhatsApp events.
2. Confirm Send WhatsApp Reply still works with current bearer credential.
3. Continue from POC Plan, Phase 1 -> Phase 2 -> Phase 3.
