# Deployment Guide - Web Client Integration

## Summary

The web client has been integrated into the Rails application and is ready for production deployment.

## What Was Integrated

- **Voice client** with spoken announcements, at `/voice_reminders`
- Rendered by Rails; announcements driven by `backend/public/voice_reminders.js`
- `/client/*` is a redirect kept for old bookmarks and already-sent magic links
- No separate deployment needed

## Production URLs

After deployment, the web client will be available at:

```
http://remindly.anakahsoft.com/client
```

Other URLs remain unchanged:
- **Caregiver Dashboard**: `http://remindly.anakahsoft.com/dashboard`
- **API**: `http://remindly.anakahsoft.com/reminders/today`
- **Login**: `http://remindly.anakahsoft.com/login`

## Deployment Steps

### 1. Push to GitHub (if not done)

```bash
git push origin feature/integrate-web-client-into-rails
```

### 2. Merge to Main

Create PR and merge, or merge locally:

```bash
git checkout main
git merge feature/integrate-web-client-into-rails
git push origin main
```

### 3. Deploy to Production

Use your existing deployment process. For example:

```bash
# If using Heroku
git push heroku main

# If using Kamal or other deployment tool
# Use your standard deployment command
```

### 4. Verify Deployment

After deployment, test:

1. **Visit**: `http://remindly.anakahsoft.com/client`
2. **Check**: Page loads with styling
3. **Login**: Click "Quick Dev Login"
4. **Test**: Create reminders and test voice announcements

## Files Deployed

The following files are included in the deployment:

```
backend/
├── public/
│   └── client/              # Web client (automatically deployed)
│       ├── index.html
│       ├── app.js
│       ├── styles.css
│       └── *.md (docs)
├── config/
│   └── routes.rb            # Route: /client -> /client/index.html
└── lib/
    └── tasks/
        └── client.rake      # Rake task for syncing
```

## Testing in Production

### Quick Test

```bash
# 1. Check if web client is accessible
curl -I http://remindly.anakahsoft.com/client

# Should return: HTTP/1.1 302 Found (redirect)

# 2. Check if index.html loads
curl -I http://remindly.anakahsoft.com/client/index.html

# Should return: HTTP/1.1 200 OK
```

### Full Test

1. Open your web browser
2. Go to: `http://remindly.anakahsoft.com/client`
3. Click "Quick Dev Login"
4. Create test reminders using Rails console:
   ```bash
   rails runner create_test_reminders.rb
   ```
5. Wait for voice announcements

## Browser Compatibility

Voice announcements work across all modern browsers:
- ✅ **Safari** - Excellent voice quality
- ✅ **Chrome** - Fully supported
- ✅ **Firefox** - Fully supported

## Troubleshooting

### CSS Not Loading

If styling doesn't load:
1. Check that `backend/public/voice_reminders.js` exists
2. Hard refresh browser (Cmd+Shift+R)
3. Check browser console for 404 errors

### Voice Not Working

1. Check browser supports Web Speech API
2. Check macOS System Settings → Accessibility → Spoken Content
3. Enable "Speak selection"
4. Test voice in Settings panel

### 404 on /client

1. Verify route exists in `config/routes.rb`
2. Check that `/voice_reminders` renders (it is a Rails view, not a static file)
3. Restart Rails server

## Updating the Voice Client

The voice client is `backend/public/voice_reminders.js`, served by Rails at
`/voice_reminders`. Edit it in place, commit, and deploy — there is no sync step.

A standalone client at `clients/web/` used to be copied into `public/client/` by
`rails client:sync`. It was superseded by `/voice_reminders` and removed; the
rake task and the duplicate copies are gone, and `/client/` redirects.

## Rollback

If you need to rollback:

```bash
# Remove the web client
git revert <commit-hash>
git push origin main
# Deploy
```

Or manually:
```bash
# Remove files
rm -rf backend/tmp/cache/

# Remove route from config/routes.rb
# Line: get "client", to: redirect("/client/index.html", status: 302)

# Commit and deploy
```

## Support

- **Voice client behaviour and its limits**: see "Voice Announcements" in the
  root `README.md`

## Success Criteria

✅ Web client accessible at `/client`
✅ Styling loads correctly
✅ Authentication works
✅ Voice announcements work
✅ Browser notifications appear
✅ All actions work (Taken, Snooze, Skip)
✅ No CORS errors
✅ Caregiver dashboard still works at `/dashboard`

---

**Ready for Production Deployment!** 🚀

Branch: `feature/integrate-web-client-into-rails`
Commit: `602a8bc`
Date: October 21, 2025
