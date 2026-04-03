# Phase 5: Authentication & Security - Setup Instructions

## Quick Start Guide

### 1. Configure Xcode URL Scheme (Required)

The app needs to handle `remindly://` URLs for magic link authentication.

**Steps:**
1. Open `clients/macos-swiftui/Remindly/Remindly.xcodeproj` in Xcode
2. Select the **Remindly** target in the project navigator
3. Click the **Info** tab
4. Scroll down to **URL Types** section
5. Click the **+** button to add a new URL Type
6. Fill in:
   - **Identifier**: `com.remindly.app`
   - **URL Schemes**: `remindly`
   - **Role**: `Editor`
7. Save and rebuild the project

**Verification:**
```bash
# Test the URL scheme works:
open "remindly://magic/verify?token=test"
# Should open the app (will show error for invalid token, but that's OK)
```

### 2. Backend Email Configuration (Development)

**Install Letter Opener for Development:**
```bash
cd backend

# Add to Gemfile
echo "gem 'letter_opener', group: :development" >> Gemfile

# Install
bundle install
```

**Configure ActionMailer:**
```bash
# Edit config/environments/development.rb
# Add these lines inside Rails.application.configure do ... end:

config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
config.action_mailer.default_url_options = { host: 'localhost', port: 5000 }
```

**Set Environment Variables:**
```bash
# Create/edit .env file in backend directory
cat > backend/.env << EOF
JWT_SECRET=dev_secret_change_me_in_production
MAILER_FROM=noreply@remindly.app
MAGIC_LINK_SCHEME=remindly
APP_URL=http://localhost:5000
EOF
```

### 3. Test the Setup

**Terminal 1 - Start Backend:**
```bash
cd backend
rails server -p 5000
```

**Terminal 2 - Launch App:**
```bash
cd clients/macos-swiftui/Remindly
open Remindly.xcodeproj
# Press Cmd+R to build and run
```

**Test Dev Mode (Quick):**
1. Enter email: `test@example.com`
2. Click "Quick Login (Dev Mode)"
3. ✅ Should authenticate immediately

**Test Magic Link (Full Flow):**
1. Enter email: `senior@example.com`
2. Click "Send Magic Link"
3. Check backend terminal for letter_opener output
4. Copy the token from the URL in the email
5. Run: `open "remindly://magic/verify?token=<TOKEN>"`
6. ✅ Should authenticate

## Production Setup

### 1. Email Service (Choose One)

#### Option A: SendGrid
```bash
# Add to backend/.env
SMTP_ADDRESS=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=your_sendgrid_api_key
MAILER_FROM=noreply@yourdomain.com
```

#### Option B: Postmark
```bash
# Add to backend/.env
SMTP_ADDRESS=smtp.postmarkapp.com
SMTP_PORT=587
SMTP_USERNAME=your_postmark_server_token
SMTP_PASSWORD=your_postmark_server_token
MAILER_FROM=noreply@yourdomain.com
```

#### Option C: AWS SES
```bash
# Add to backend/.env
SMTP_ADDRESS=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587
SMTP_USERNAME=your_aws_access_key
SMTP_PASSWORD=your_aws_secret_key
MAILER_FROM=noreply@yourdomain.com
```

### 2. Configure Production Environment

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :smtp
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true

config.action_mailer.smtp_settings = {
  address: ENV['SMTP_ADDRESS'],
  port: ENV['SMTP_PORT'].to_i,
  user_name: ENV['SMTP_USERNAME'],
  password: ENV['SMTP_PASSWORD'],
  authentication: :plain,
  enable_starttls_auto: true
}

config.action_mailer.default_url_options = { 
  host: ENV['APP_DOMAIN'], 
  protocol: 'https' 
}
```

### 3. Set Production Environment Variables

```bash
# Production .env (or use your hosting platform's env vars)
JWT_SECRET=<generate_secure_random_string>
MAILER_FROM=noreply@yourdomain.com
MAGIC_LINK_SCHEME=remindly
APP_URL=https://yourdomain.com
APP_DOMAIN=yourdomain.com

# SMTP settings (from your email provider)
SMTP_ADDRESS=smtp.yourprovider.com
SMTP_PORT=587
SMTP_USERNAME=your_username
SMTP_PASSWORD=your_password
```

**Generate Secure JWT Secret:**
```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
```

## Troubleshooting

### URL Scheme Not Working

**Problem:** Clicking magic link doesn't open the app

**Solutions:**
1. Verify URL scheme is added in Xcode Info tab
2. Clean build folder: Product > Clean Build Folder (Cmd+Shift+K)
3. Delete app from Applications and rebuild
4. Check Console.app for errors
5. Test with: `open "remindly://test"`

### Email Not Sending

**Problem:** Magic link email not received

**Development:**
1. Check backend logs: `tail -f backend/log/development.log`
2. Verify letter_opener is installed: `bundle list | grep letter_opener`
3. Check for email in terminal output
4. Try `deliver_now` instead of `deliver_later` for testing

**Production:**
1. Check SMTP credentials are correct
2. Verify sender email is authorized
3. Check spam folder
4. Review email service logs (SendGrid, Postmark, etc.)
5. Test SMTP connection:
```ruby
# In Rails console
ActionMailer::Base.smtp_settings
# Should show your SMTP config
```

### Token Expired Error

**Problem:** Magic link shows "expired" error

**Solutions:**
1. Magic links expire after 30 minutes (by design)
2. Request a new magic link
3. Check system time is correct
4. Verify backend time zone settings

### Keychain Access Denied

**Problem:** Can't save token to Keychain

**Solutions:**
1. Check app signing and entitlements
2. Reset Keychain: Keychain Access > Preferences > Reset
3. Grant Keychain access when prompted
4. Check Console.app for Keychain errors

## Testing Checklist

- [ ] URL scheme configured in Xcode
- [ ] Backend running on localhost:5000
- [ ] Letter Opener installed (development)
- [ ] Environment variables set
- [ ] Dev mode login works
- [ ] Magic link email sends
- [ ] Magic link opens app
- [ ] Authentication persists after restart
- [ ] Logout works
- [ ] Account settings show email
- [ ] Token expiration handled

## Files Modified/Created

### New Files
- `clients/macos-swiftui/Remindly/Remindly/AuthenticationManager.swift`
- `clients/macos-swiftui/Remindly/Remindly/LoginView.swift`
- `backend/app/mailers/magic_mailer.rb`
- `backend/app/views/magic_mailer/magic_link_email.html.erb`
- `backend/app/views/magic_mailer/magic_link_email.text.erb`

### Modified Files
- `clients/macos-swiftui/Remindly/Remindly/RemindlyApp.swift`
- `clients/macos-swiftui/Remindly/Remindly/ReminderVM.swift`
- `clients/macos-swiftui/Remindly/Remindly/SettingsView.swift`
- `backend/app/controllers/magic_controller.rb`

## Next Steps

1. **Configure URL Scheme** (required for magic links)
2. **Test Dev Mode** (quick verification)
3. **Test Magic Link Flow** (full authentication)
4. **Configure Production Email** (when deploying)
5. **Update Config.swift** with production API URL

## Support

For detailed implementation guide, see: [SPRINT_5_AUTHENTICATION_GUIDE.md](SPRINT_5_AUTHENTICATION_GUIDE.md)

For overall project plan, see: [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md)
