# Email setup (Resend)

Supabase's built-in email service is capped at a few messages per hour and is
explicitly not for production use. Once more than a couple of people are
signing up, confirmation and reset emails start silently failing.

Pointing Supabase at [Resend](https://resend.com) fixes that. Resend's free
tier is 3,000 emails/month (100/day), which is plenty for a team tool.

This is dashboard configuration only — no application code is involved.

---

## Quick start: no domain, 5 minutes

If you do not control a domain's DNS yet, skip the verification steps and use
Resend's shared sender. This is enough to test sign-up and see the templates
render properly.

1. Sign up at [resend.com](https://resend.com) **using the address you want to
   receive test emails at** — this matters, see the warning below.
2. **API Keys → Create API Key** → name it `Supabase`, permission
   **Sending access** → copy the key (`re_...`).
3. In Supabase: **Project Settings → Authentication → SMTP Settings →
   Enable Custom SMTP**, and fill in:

   | Field | Value |
   |---|---|
   | Sender email | `onboarding@resend.dev` — exactly this |
   | Sender name | `Planner` |
   | Host | `smtp.resend.com` |
   | Port | `465` |
   | Username | `resend` |
   | Password | your `re_...` API key |

   > `onboarding@resend.dev` is the only address Resend allows without a
   > verified domain. `noreply@resend.dev` and anything else on that domain are
   > rejected, because `resend.dev` belongs to Resend rather than to you. Use
   > `noreply@yourdomain.com` once you have verified a domain of your own.
   >
   > Recipients see the **Sender name**, so the inbox shows "Planner" regardless.

4. Save.
5. **Authentication → Rate Limits** → raise **"Rate limit for sending emails"**
   to e.g. 100/hour. Supabase keeps its own low limit even with custom SMTP, and
   leaving it throttles sign-ups regardless of Resend.

> **The one catch:** `onboarding@resend.dev` only delivers to the email address
> your Resend account is registered to. Sign-ups from any other address will
> fail. That is fine for testing your own account; inviting teammates needs a
> verified domain — continue below when you are ready.

---

## 1. Create a Resend account and verify a domain

1. Sign up at [resend.com](https://resend.com).
2. Go to **Domains → Add Domain** and enter a domain you control
   (e.g. `yourcompany.com`).
3. Resend shows a set of DNS records — typically `MX`, plus `TXT` records for
   SPF, DKIM and DMARC. Add them at your DNS provider.
4. Wait for verification (usually minutes; DNS can take up to an hour).

> **No domain of your own?** You can send from Resend's shared
> `onboarding@resend.dev` sender for testing, but it only delivers to the email
> address you signed up with. Fine for verifying the setup works; not usable for
> real invitations.

**Why a verified domain matters:** SPF and DKIM prove the mail genuinely comes
from your domain. Without them, Gmail and Outlook route confirmation emails
straight to spam — which looks to your users like sign-up being broken.

## 2. Create an SMTP credential

1. In Resend, open **SMTP** (or **API Keys → Create**, with SMTP access).
2. Copy the credentials. You need:
   - Host: `smtp.resend.com`
   - Port: `465` (SSL) or `587` (STARTTLS)
   - Username: `resend`
   - Password: your API key (`re_...`)

Copy the key now — Resend only shows it once.

## 3. Point Supabase at Resend

In the Supabase dashboard:

**Project Settings → Authentication → SMTP Settings → Enable Custom SMTP**

| Field | Value |
|---|---|
| Sender email | `noreply@yourdomain.com` (must be on the verified domain) |
| Sender name | `Planner` |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | your Resend API key |

Save, then use **Send test email** to confirm delivery before relying on it.

### Raise the rate limit

Supabase keeps a conservative auth email rate limit even after you attach your
own SMTP. Under **Authentication → Rate Limits**, raise
**"Rate limit for sending emails"** to something appropriate (e.g. 100/hour).
Leaving it at the default silently throttles sign-ups.

## 4. Where the API key lives

The Resend key is entered **into the Supabase dashboard**, not into this
repository. It never appears in `.env`, in the Flutter app, or in the built
binary — Supabase's auth server sends the mail, so the app never touches it.

Do not add the Resend key to `.env`. Nothing in the app reads it, and anything
in a client binary is recoverable by whoever has the app.

## 5. Email templates

**Authentication → Email Templates** in Supabase. Each template supports
variables like `{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .SiteURL }}`.

Ready-made templates matching the app's design are in
[`supabase/email-templates/`](email-templates/):

| File | Supabase template |
|---|---|
| `confirm-signup.html` | Confirm signup |
| `reset-password.html` | Reset password |
| `magic-link.html` | Magic Link |
| `invite.html` | Invite user |

Paste the file contents into the matching template and save.

They use inline CSS and table layout — not because that is pleasant, but
because Outlook's rendering engine ignores most modern CSS, and a stylesheet
that works in a browser routinely collapses there.

---

## Troubleshooting

**Test email works, real sign-ups do not.** Almost always the Supabase auth
rate limit (step 3), not Resend.

**Emails land in spam.** Check the domain is fully verified in Resend, with
DKIM and DMARC present and not just SPF. Sending from a `noreply@` address on a
verified domain matters more than the message content.

**"Error sending confirmation email" on sign-up.** The SMTP credentials are
wrong, or the sender address is not on a verified domain. Supabase logs the
underlying SMTP error under **Logs → Auth**.

**Nothing arrives and there is no error.** Check Resend's **Emails** dashboard —
it shows delivered, bounced and complained. If a message is not there at all,
Supabase never attempted it; if it bounced, the receiving server rejected it.
