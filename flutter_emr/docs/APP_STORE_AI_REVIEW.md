# App Store Review — AI data sharing (Guideline 5.1.2(i))

Paste the following into **App Store Connect → App Review Information → Notes** when resubmitting.

---

## AI features in this app

The app offers **optional** AI assistance (patient symptom chat, medical record summaries, doctor SOAP drafting). AI is **not** used for advertising, profiling, or training third-party models.

## Third-party AI service

Yes — user health-related **text** is sent to our backend for AI inference:

| Item | Detail |
|------|--------|
| **Recipient** | Innovator Generation |
| **Endpoint** | `https://api.docsoncalls.com/api/medical-records/ai-assist/` (HTTPS) |
| **AI engine** | **Ollama** (open-source LLM) on servers we operate — not OpenAI/ChatGPT/Google Gemini |

## In-app disclosure (not policy-only)

Before the first AI request, the app shows a dialog that explains:

1. **What data is sent** — typed/dictated text; optional record excerpts when summarizing  
2. **Who receives it** — Docs On Call API + Ollama on our infrastructure  
3. **User permission** — **Don’t Allow** / **Allow & Continue**  
4. Link to **Privacy Policy** (`https://docsoncalls.com/privacy.html`)

AI screens also display a persistent banner describing AI data sharing.

## Revoking consent

**Settings → AI data sharing → Revoke** (iOS app build 1.0.16+).

## Privacy policy

Updated at https://docsoncalls.com/privacy.html with AI collection, recipients, uses, and safeguards.

## How to test

1. Sign in as patient: `role_patient_only@local.test` / `DemoPass2026!` (or your test account)  
2. Open **AI assistant** tab → type a message → tap Send  
3. Confirm consent dialog appears before network AI call  
4. Tap **Don’t Allow** — no data should be sent to `/medical-records/ai-assist/`  
5. Tap **Allow & Continue** — request proceeds  
6. **Settings → AI data sharing → Revoke** — next AI use prompts again  

## Emergency disclaimer

AI is labeled as not for emergencies; users are directed to call local emergency services for severe symptoms.
