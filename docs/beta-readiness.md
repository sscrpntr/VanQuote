# Beta readiness follow-up

## Email setup for Vercel production

The app is prepared to send through Gmail SMTP as `theoriginalvanquote@gmail.com`. In Google's account security settings, enable two-step verification and create an app password for this app. Do not use the account's normal password.

### Local development

Add the following to the ignored `.env.local` file in the repository root. Keep the app password out of source control and chat:

```dotenv
GMAIL_SMTP_USERNAME=theoriginalvanquote@gmail.com
GMAIL_SMTP_APP_PASSWORD=your-Google-app-password
ADMIN_NOTIFICATION_EMAIL=sergiescarpenter@gmail.com
```

Development loads `.env.local` before configuring Action Mailer, uses Gmail SMTP with STARTTLS on port 587, and raises delivery errors. Restart `bin/rails server` after changing the file. Without `GMAIL_SMTP_APP_PASSWORD`, actual SMTP delivery will fail visibly; mailer tests use Rails' test delivery adapter and do not need this credential.

After configuring a valid app password, a controlled SMTP check can send one message to the administrator's own inbox from a Rails console:

```ruby
ActionMailer::Base.mail(
  from: "theoriginalvanquote@gmail.com",
  to: "sergiescarpenter@gmail.com",
  subject: "VanQuote SMTP connectivity check",
  body: "Controlled local SMTP check."
).deliver_now
```

An SMTP success response means the server accepted the message for delivery; confirm inbox or spam-folder receipt separately.

In Vercel, open the VanQuote project, then **Settings → Environment Variables**. Add these variables for **Production** only:

- `GMAIL_SMTP_USERNAME`: `theoriginalvanquote@gmail.com`
- `GMAIL_SMTP_APP_PASSWORD`: the Google app password
- `ADMIN_NOTIFICATION_EMAIL`: `sergiescarpenter@gmail.com`
- `APP_HOST`: the production hostname without `https://` (for example `vanquote.es`)

## Password reset protection

Rails uses an explicitly configured encrypted cookie session. Its cookie is `HttpOnly` and `SameSite=Lax`; the `Secure` flag is enabled in production and disabled for local HTTP development. The setting has not been verified against a live Vercel request/proxy, so confirm the deployed response includes `Secure` before release.

Migration `20261009180000` adds PostgreSQL unique indexes enforcing one lead per quote and at most one administrator. It has been applied to the local development and test databases only. Before applying it in production, verify there are no duplicate `leads.quote_id` values and no more than one admin row.

Password reset requests use PostgreSQL-backed, fixed-window limits shared by all application instances. The table stores HMAC digests for the IP and normalized email, not either raw value. Requests are limited to 10 per IP per 3 minutes and 5 per account per 15 minutes. Denied requests do not extend the current window; expired rows are removed in bounded batches during later reset requests. The account limit blocks only new reset emails during its window; it does not invalidate an already issued link or lock the account out of sign-in.

A single burst therefore causes a bounded delay. A sustained distributed attacker could still keep triggering fresh windows and temporarily suppress reset emails; this is request throttling, not a guarantee against denial of service. Because known accounts trigger synchronous mail delivery and unknown accounts do not, response timing may still differ despite the generic response and shared limits.

Before deploying the password reset changes, configure `PASSWORD_RESET_RATE_LIMIT_SECRET` for the Production environment in Vercel. Generate a unique 32-byte key locally with:

```sh
openssl rand -hex 32
```

Enter the generated value directly in Vercel's **Settings → Environment Variables**. Do not put it in Git or paste it into chat. The production recovery endpoint fails closed and sends no email if the variable is missing or is not 64 hexadecimal characters. Local development and tests use Rails' `secret_key_base` only when this dedicated variable is absent.

The release must apply the additive password-reset migration to the production PostgreSQL database before the new code serves reset requests. This repository task does not run production migrations, configure Vercel, or deploy. The reset email link places the signed token in the URL fragment; the browser removes it from the address bar and submits it in a filtered POST body. Rails consumes it once, then stores only a short-lived user authorization in the encrypted, non-persistent session. A first successful token use invalidates other outstanding reset links for that account.

Redeploy from Vercel after entering them. Do not paste credentials into chat or commit them. The sender identity remains the Gmail account above. Delivery acceptance by SMTP is not proof that a message reached the inbox; verify with controlled test accounts after configuration. A dedicated transactional email service may be more reliable as volume grows, but it requires a verified sending domain and is not configured here.

## Administrator activation

Have Sergi register through Google using `sergiescarpenter@gmail.com` and accept the terms. Run `bin/rails users:promote_beta_admin` only after verifying the intended database target. The task refuses to promote an unverified or unlinked account and refuses to change anything if another administrator exists. Verify the account can open `/admin` and a normal account receives HTTP 403.

## Future pricing review — non-priority

- Fuel: €0.12/km.
- Vehicle: €0.10/km.
- Driver: €25/hour.
- Margin: 25%.
- Tolls: currently €0.
- Current calculation covers one-way trips only.

Do not change these assumptions as part of the beta security work; review them separately with business input.
