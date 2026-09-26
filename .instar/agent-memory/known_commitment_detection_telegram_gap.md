---
name: commitment-detection-telegram-gap
description: Commitment-detection job disabled; requires Telegram which is not configured on this agent
metadata: 
  node_type: memory
  type: known
  originSessionId: 467b0305-eedb-41f5-b6ab-5c57ba85f07f
  modified: 2026-07-28T12:02:20.007Z
---

## Issue

The `commitment-detection` job runs every 5 minutes scanning `.instar/telegram-messages.jsonl` for commitment markers ("I will", "let me", etc.) and registering them via `POST /evolution/actions`.

**Problem:** Telegram is not configured on this agent. The message log is always empty. The job finds nothing every 5 minutes—structural overhead with zero function.

**How commitments actually work here:** The user creates commitments via `POST /commitments` API directly during Claude Code sessions (Adrian is the operator). The commitments store (`GET /commitments`) already has 11+ tracked items. No Telegram scanning needed.

## Status

**2026-07-28 05:00+ — RESOLVED**

Changed `.instar/jobs/schedule/commitment-detection.json`: `enabled: false`. Server restarted to load the new config. Job is now properly disabled in the running scheduler (verified via `GET /jobs`).

Matches the precedent set by dashboard-link-refresh job disabling (same root cause: "no Telegram adapter on this machine").

## Why this matters

This was a scope-coherence check trigger: the job was running without purpose, and I was mechanically executing it rather than asking "Is this job actually appropriate for this agent's usage pattern?" The answer is no.
