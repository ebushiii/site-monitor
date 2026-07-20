# Eugenius Site Monitor

Checks every site in [sites.txt](sites.txt) every ~5 minutes from GitHub's servers.
When a site goes down (or comes back up) you get:

1. **A text message** from the Eugenius line (773) 985-6816 — once Twilio secrets are set (below).
2. **An email from GitHub** (built-in, already active) — the workflow run fails once per new outage.

A site counts as **down** only after 3 failed attempts ~10 seconds apart (connection failure or HTTP 4xx/5xx), so a single network blip won't page you. You get exactly one "down" alert per outage and one "recovered" alert when it's back, with the outage length.

## Add a new site

Edit `sites.txt` — one URL per line — and push (or edit right on github.com). That's it.

## Turn on text alerts (one-time setup)

Add three Actions secrets — either on github.com under
**Settings → Secrets and variables → Actions**, or from any terminal:

```bash
gh secret set TWILIO_ACCOUNT_SID --repo ebushiii/site-monitor   # ACxxxxxxxx... from console.twilio.com
gh secret set TWILIO_AUTH_TOKEN  --repo ebushiii/site-monitor   # auth token from console.twilio.com
gh secret set ALERT_PHONE        --repo ebushiii/site-monitor   # your cell, e.g. +1773XXXXXXX
```

Texts come from the Twilio number that also powers Eugenius calls: **+1 (773) 985-6816**.
(To send from a different Twilio number, add an optional `TWILIO_FROM` secret.)

Until the secrets are set, the monitor still runs and GitHub email alerts still work;
the SMS step just logs what it *would* have texted.

## Notes

- Current status lives in [state.json](state.json) (committed automatically on changes).
- GitHub cron isn't exact — checks land every 5–15 minutes in practice.
- A monthly heartbeat commit keeps GitHub from auto-pausing the schedule after 60 days of repo inactivity.
