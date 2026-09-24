# Email Authentication Setup for remindly.care

This guide explains how to set up SPF, DKIM, and DMARC for the `remindly.care` domain to ensure email deliverability and prevent spoofing.

## Overview

The app sends emails from: `notifications@remindly.care`

You need to configure DNS records to authenticate these emails.

## Prerequisites

- Access to your DNS provider for `remindly.care`
- Email service provider (choose one):
  - **Postmark** (recommended for transactional emails)
  - **SendGrid**
  - **AWS SES**
  - **Mailgun**

## Step 1: Choose an Email Service Provider

### Option A: Postmark (Recommended)

1. Sign up at https://postmarkapp.com
2. Add `remindly.care` as a sender domain
3. Postmark will provide you with DNS records to add

### Option B: SendGrid

1. Sign up at https://sendgrid.com
2. Go to Settings → Sender Authentication
3. Authenticate your domain `remindly.care`

### Option C: AWS SES

1. Go to AWS SES console
2. Verify `remindly.care` domain
3. Follow the DNS verification steps

## Step 2: Add DNS Records

Your email provider will give you specific DNS records. Here's what you'll typically need to add:

### SPF Record (TXT)

Authorizes which servers can send email from your domain.

```
Type: TXT
Name: @
Value: v=spf1 include:spf.youremailprovider.com ~all
TTL: 3600
```

**Example for Postmark:**
```
v=spf1 include:spf.mtasv.net ~all
```

### DKIM Records (TXT)

Cryptographically signs your emails.

```
Type: TXT
Name: pm._domainkey (or similar, provided by your email service)
Value: [Long cryptographic key provided by your email service]
TTL: 3600
```

### DMARC Record (TXT)

Tells receiving servers what to do with emails that fail SPF/DKIM.

```
Type: TXT
Name: _dmarc
Value: v=DMARC1; p=none; rua=mailto:dmarc@remindly.care
TTL: 3600
```

**Recommended DMARC policies:**
- Start with `p=none` (monitor only)
- After 1-2 weeks, upgrade to `p=quarantine`
- Eventually use `p=reject` for maximum protection

## Step 3: Configure Rails to Use Your Email Provider

### For Postmark

1. Add gem to Gemfile:
```ruby
gem 'postmark-rails'
```

2. Update `config/environments/production.rb`:
```ruby
config.action_mailer.delivery_method = :postmark
config.action_mailer.postmark_settings = { 
  api_token: Rails.application.credentials.dig(:postmark, :api_token)
}
```

3. Add API token to credentials:
```bash
bin/rails credentials:edit
```

Add:
```yaml
postmark:
  api_token: your-postmark-api-token-here
```

### For SendGrid

1. Add gem:
```ruby
gem 'sendgrid-ruby'
```

2. Configure SMTP settings in production.rb:
```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  user_name: 'apikey',
  password: Rails.application.credentials.dig(:sendgrid, :api_key),
  domain: 'remindly.care',
  address: 'smtp.sendgrid.net',
  port: 587,
  authentication: :plain,
  enable_starttls_auto: true
}
```

## Step 4: Verify DNS Records

After adding DNS records, verify them:

```bash
# Check SPF
dig TXT remindly.care

# Check DKIM (replace with your actual DKIM selector)
dig TXT pm._domainkey.remindly.care

# Check DMARC
dig TXT _dmarc.remindly.care
```

Or use online tools:
- https://mxtoolbox.com/SuperTool.aspx
- https://dmarcian.com/dmarc-inspector/

## Step 5: Test Email Delivery

1. Deploy the updated configuration
2. Send a test invitation email
3. Check email headers to verify SPF, DKIM, DMARC pass
4. Use https://www.mail-tester.com/ to test deliverability score

## Step 6: Monitor

- Check DMARC reports sent to `dmarc@remindly.care`
- Monitor bounce rates in your email provider dashboard
- Gradually tighten DMARC policy from `none` → `quarantine` → `reject`

## Current Configuration

✅ Email sender: `notifications@remindly.care`
✅ Default URL host: `remindly.care`
✅ Raise delivery errors enabled

⏳ Pending:
- [ ] Choose email service provider
- [ ] Add DNS records (SPF, DKIM, DMARC)
- [ ] Configure Rails with provider credentials
- [ ] Test email delivery
- [ ] Monitor and adjust DMARC policy

## Troubleshooting

### Emails going to spam
- Verify all DNS records are correct
- Check SPF/DKIM/DMARC alignment
- Warm up your sending domain gradually
- Ensure consistent "From" address

### DNS propagation delays
- DNS changes can take up to 48 hours
- Use `dig` to check if records are visible
- Some providers cache DNS longer than others

### Authentication failures
- Double-check DKIM selector matches
- Ensure SPF includes your email provider
- Verify DMARC policy isn't too strict initially
