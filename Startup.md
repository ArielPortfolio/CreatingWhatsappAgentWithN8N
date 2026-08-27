This was my chat with Claude regarding an agent I want to create with n8n:

# WhatsApp AI Personal Assistant — n8n Build Starter Doc

> This document summarizes a planning conversation to be used as context for a Copilot consultation session.

---

## 🎯 Goal

Build a personal AI assistant that I can talk with on **WhatsApp**. The agent will have access to my **Google Calendar**, **Gmail**, and **Google Drive**, and I should be able to ask it things like:

- *"What do you have planned for today?"*
- *"Set a meeting with X on the calendar"*
- *"What does it say on doc 'abc' in my Google Drive?"*

---

## 🧠 Chosen AI Model: Google Gemini 2.5 Flash (Free Tier)

- Free API key via [Google AI Studio](https://aistudio.google.com) — no credit card required
- **Rate limits (free tier):** 10 requests/minute, 250 requests/day — sufficient for personal use
- Native fit with Google ecosystem (Calendar, Gmail, Drive)
- n8n has a built-in **Google Gemini Chat Model node**

---

## 🛠️ Chosen Automation Platform: n8n

- Open-source, visual workflow automation tool
- Has native built-in nodes for: WhatsApp, Gmail, Google Calendar, Google Drive, Gemini
- **Hosting decision:** n8n Cloud (free 14-day trial, then ~€24/month Starter) OR self-hosted on a VPS (e.g. Hetzner CX22, ~€7/month, 2 vCPUs / 4GB RAM)
- Workflows are triggered by **webhook** (WhatsApp message arrives → agent responds), so execution quota usage is minimal

---

## 🏗️ Agent Architecture

```
WhatsApp message (user)
        ↓
  n8n WhatsApp Trigger (webhook)
        ↓
    AI Agent Node
    (Gemini 2.5 Flash)
        ↓
  ┌─────┼──────────┐
  ↓     ↓          ↓
Gmail  Google    Google
       Calendar   Drive
        ↓
WhatsApp reply (back to user)
```

---

## ✅ Build Steps (Planned)

1. **Get Gemini API key** → [aistudio.google.com](https://aistudio.google.com), sign in, click "Get API Key"
2. **Set up n8n** → start with n8n Cloud free trial
3. **Connect Google services** → use n8n's built-in OAuth nodes for Gmail, Calendar, Drive
4. **Set up WhatsApp Business API** → requires Meta Business verification (trickiest step)
5. **Wire the AI Agent node** → use Gemini as the brain, Google tools as actions
6. **Test end-to-end** → send a WhatsApp message, verify agent responds correctly

---

## 📌 Key Technical Notes

- **WhatsApp trigger type:** webhook-based (not polling) — agent only runs when a message arrives, so no wasted executions
- **n8n workflow format:** exportable as JSON — paste into Copilot for debugging help
- **Google OAuth:** n8n handles this via its credentials manager — one-time setup per service
- **Memory:** n8n supports session memory per user for follow-up conversations
- **Background operation:** agent runs 24/7 on the cloud/VPS — independent of local machine

---

## 🙋 My Background (Relevant Context)

- Senior C# / .NET developer, 10+ years experience
- Familiar with distributed systems, event-driven architecture, Azure, RabbitMQ
- Comfortable with APIs, JSON, OAuth flows
- Not a complete beginner — can handle technical explanations

---

## ❓ What I Need Help With (Guide me step by step through):

1. Setting up the n8n WhatsApp trigger with Meta Business API
2. Configuring the AI Agent node with Gemini 2.5 Flash
3. Connecting Gmail, Google Calendar, and Google Drive as tools
4. Testing and debugging the end-to-end flow
5. Handling memory so the agent remembers context across messages

