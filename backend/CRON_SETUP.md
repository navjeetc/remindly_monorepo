# Cron Setup for Production

Since the Docker container doesn't include cron, we need to set up the cron job on the host server.

## Option 1: Host Server Cron (Recommended)

SSH into the server and set up a cron job that executes the rake task inside the container:

```bash
# SSH into the server
ssh $USER@$SERVER_IP

# Edit crontab
crontab -e

# Add this line (runs at 10 PM daily)
0 22 * * * cd $HOME && docker exec $(docker ps --filter "label=service=remindly-backend" --filter "label=role=web" --format "{{.ID}}" | head -1) bin/rails audit:daily_report >> $HOME/audit_cron.log 2>&1
```

### Explanation:
- `0 22 * * *` - Runs at 10:00 PM every day
- `docker ps --filter ...` - Finds the running web container
- `docker exec ... bin/rails audit:daily_report` - Executes the rake task inside the container
- `>> $HOME/audit_cron.log 2>&1` - Logs output to a file

## Option 2: Kamal Accessory with Cron

Add a cron accessory to `config/deploy.yml`:

```yaml
accessories:
  cron:
    image: alpine:latest
    host: 161.35.104.56
    cmd: >
      sh -c "
      apk add --no-cache docker-cli &&
      echo '0 22 * * * docker exec \$(docker ps --filter label=service=remindly-backend --filter label=role=web --format {{.ID}} | head -1) bin/rails audit:daily_report' | crontab - &&
      crond -f -l 2
      "
```

Then deploy:
```bash
kamal accessory boot cron
```

## Option 3: External Cron Service

Use an external service like:
- **Cron-job.org** - Free web-based cron service
- **EasyCron** - Cron as a service
- **AWS EventBridge** - If using AWS

Set up a webhook endpoint and have the service hit it at 10 PM daily.

## Verify Cron is Running

### Check crontab on host:
```bash
ssh navjeetc@161.35.104.56
crontab -l
```

### Check cron logs:
```bash
ssh navjeetc@161.35.104.56
tail -f /home/navjeetc/audit_cron.log
```

### Test manually:
```bash
# On host server
docker exec $(docker ps --filter "label=service=remindly-backend" --filter "label=role=web" --format "{{.ID}}" | head -1) bin/rails audit:daily_report
```

## Environment Variables

Make sure `AUDIT_REPORT_EMAIL` is set in your Kamal secrets:

```bash
# .kamal/secrets
AUDIT_REPORT_EMAIL=your@email.com
```

Or use Rails credentials:
```bash
# On your local machine
EDITOR=nano rails credentials:edit

# Add:
audit_report_email: your@email.com

# Deploy
kamal deploy
```

## Troubleshooting

### Cron not running:
1. Check crontab is installed: `crontab -l`
2. Check cron service: `systemctl status cron` or `service cron status`
3. Check logs: `tail -f /home/navjeetc/audit_cron.log`

### Email not sending:
1. Test manually: `kamal app exec 'bin/rails audit:daily_report'`
2. Check Rails logs: `kamal app logs -f`
3. Verify email configuration in credentials

### Wrong time:
1. Check server timezone: `timedatectl`
2. Adjust cron time accordingly
3. Or set timezone in cron: `TZ=America/New_York 0 22 * * * ...`
