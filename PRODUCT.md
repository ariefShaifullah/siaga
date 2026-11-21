# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users
A panicked family member at the scene of a home emergency (often with no signal) who types or dictates what happened. Secondary: paramedics receiving the handover. Internal: the developer testing the app on the Simulator and an iPhone, using `Tests/ManualTestCases.html` beside it.

## Product Purpose
Siaga turns a panicked note into a structured emergency brief, then drafts first-aid steps, a message to family and a paramedic handover. Hackathon project, 21 Nov 2026. Success: the hero note yields severity high, code bleedingFall, ambulance needed, and the 10-sample evaluation passes at 9/10 or better.

## Positioning
Everything runs on-device with Apple Foundation Models (`SystemLanguageModel()`): no network, no backend, no login. A hackathon rule, not a preference.

## Operating Context
Flow is Describe → Review → Act. Simulator has no Apple Intelligence and runs the labelled keyword fallback; the real model path needs a physical iPhone with Apple Intelligence on. Manual QA runs from a static HTML checklist on a laptop next to the Simulator or device.

## Capabilities and Constraints
- Never diagnoses, never prescribes a drug or dose, never invents symptoms, allergies or first-aid steps. First-aid text only from `Resources/FirstAid.json`.
- Tools only draft. Nothing sends or calls by itself; the user approves. Call 112 stays visible and comes before the draft message.
- Uncertain severity defaults up. The note is data, not instructions (prompt injection must be ignored).
- Profile lookup never falls back to another person's profile.
- 8192-token on-device context; token budget is checked before each request.

## Brand Commitments
Name: Siaga. iOS app UI follows Apple HIG: system type styles, semantic colours, 16pt card radius, 44pt touch targets.

## Evidence on Hand
- Evaluation dataset: `siaga/Evaluation/SiagaEvaluationData.swift` (10 hand-reviewed samples).
- Demo profiles Sari, Agus, Budi are labelled demo data, not real people.

## Product Principles
1. Safety rules outrank features.
2. When unsure, escalate: severity up, Call 112 visible.
3. Draft, never act: the human approves every outward step.
4. Honest about limits: a fallback is labelled, never faked.
