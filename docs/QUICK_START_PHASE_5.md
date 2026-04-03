# Phase 5: Quick Start Guide

## 🚀 Get Started in 5 Minutes

### Step 1: Configure URL Scheme (2 minutes)

1. Open `clients/macos-swiftui/Remindly/Remindly.xcodeproj` in Xcode
2. Select **Remindly** target → **Info** tab
3. Under **URL Types**, click **+** and add:
   - **Identifier:** `com.remindly.app`
   - **URL Schemes:** `remindly`
   - **Role:** `Editor`

### Step 2: Install Letter Opener (1 minute)

```bash
cd backend
echo "gem 'letter_opener', group: :development" >> Gemfile
bundle install
```

### Step 3: Configure Email (1 minute)

Edit `backend/config/environments/development.rb` and add inside the `configure` block:

```ruby
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
```

### Step 4: Start Backend (30 seconds)

```bash
cd backend
rails server -p 5000
```

### Step 5: Test It! (30 seconds)

1. Open Xcode and run the app (Cmd+R)
2. Enter email: `test@example.com`
3. Click **"Quick Login (Dev Mode)"**
4. ✅ You're authenticated!

## 🧪 Test Magic Link Flow

1. Enter email: `senior@example.com`
2. Click **"Send Magic Link"**
3. Check backend terminal for letter_opener output
4. Copy the token from the email URL
5. Run in terminal:
   ```bash
   open "remindly://magic/verify?token=<YOUR_TOKEN>"
   ```
6. ✅ App authenticates via magic link!

## 📝 What You Get

- ✅ Secure JWT storage in Keychain
- ✅ Magic link authentication
- ✅ Session persistence
- ✅ Auto-logout on token expiration
- ✅ Account settings with logout
- ✅ Dev mode for quick testing

## 📚 Full Documentation

- **Implementation Guide:** [SPRINT_5_AUTHENTICATION_GUIDE.md](SPRINT_5_AUTHENTICATION_GUIDE.md)
- **Setup Instructions:** [PHASE_5_SETUP_INSTRUCTIONS.md](PHASE_5_SETUP_INSTRUCTIONS.md)
- **Summary:** [PHASE_5_SUMMARY.md](PHASE_5_SUMMARY.md)

## 🆘 Troubleshooting

**URL scheme not working?**
- Clean build: Cmd+Shift+K
- Rebuild and reinstall app

**Email not sending?**
- Check backend logs: `tail -f backend/log/development.log`
- Verify letter_opener is installed: `bundle list | grep letter_opener`

**Token expired?**
- Magic links expire after 30 minutes
- Request a new one

## 🎉 You're Done!

Phase 5 is complete. Your app now has secure, passwordless authentication!

**Next:** Test the full flow and move to Phase 6 or 7.
