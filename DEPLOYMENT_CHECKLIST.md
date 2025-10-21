# Remindly Backend Deployment Checklist

Based on your existing gifter app deployment setup.

## Pre-Deployment Setup

### 1. DigitalOcean VPS
- [ ] Create or identify existing DigitalOcean Droplet
- [ ] Note the IP address
- [ ] Ensure SSH access with `navjeetc` user
- [ ] Verify Docker is installed on VPS

### 2. Domain Configuration
- [ ] Set up DNS A record: `api.remindly.anakhsoft.com` → VPS IP
- [ ] Wait for DNS propagation (check with `dig api.remindly.anakhsoft.com`)

### 3. DigitalOcean Container Registry
- [ ] Verify access to `registry.digitalocean.com/anakhsoft`
- [ ] Get or create API token from: https://cloud.digitalocean.com/account/api/tokens
- [ ] Token needs read/write access to container registry

### 4. Rails Production Credentials
```bash
cd backend
EDITOR=nano rails credentials:edit --environment production
```
This creates `config/credentials/production.key` - save this securely!

### 5. Create Secrets File
```bash
cd backend
mkdir -p .kamal
cp .kamal/secrets.example .kamal/secrets
chmod 600 .kamal/secrets
```

Edit `.kamal/secrets` with your actual values:
```bash
KAMAL_REGISTRY_PASSWORD=dop_v1_xxxxxxxxxxxxx  # Your DO token
RAILS_MASTER_KEY=xxxxxxxxxxxxxxxxxxxxxxxx     # From step 4
```

### 6. Update deploy.yml
Edit `backend/config/deploy.yml`:
- Line 10: Replace `YOUR_VPS_IP_HERE` with actual IP
- Line 15: Confirm domain `api.remindly.anakhsoft.com` is correct

## Deployment Steps

### First Time Setup

```bash
cd backend

# Verify configuration
kamal config

# Setup infrastructure (first time only)
kamal setup

# This will:
# - Install Docker on VPS (if needed)
# - Set up Traefik proxy
# - Configure SSL with Let's Encrypt
# - Deploy the application
```

### Subsequent Deployments

```bash
cd backend

# Deploy updates
kamal deploy

# View logs
kamal app logs -f

# Check status
kamal app details
```

## Post-Deployment Verification

### 1. Check Application Health
```bash
# Check if app is running
kamal app details

# View recent logs
kamal app logs --tail 50

# Test endpoint
curl https://api.remindly.anakhsoft.com/health
```

### 2. Database Setup
```bash
# Run migrations
kamal app exec "bin/rails db:migrate"

# Seed database (if needed)
kamal app exec "bin/rails db:seed"
```

### 3. Rails Console Access
```bash
# Access Rails console
kamal console

# Or using full command
kamal app exec --interactive --reuse "bin/rails console"
```

### 4. Verify SSL Certificate
- Visit https://api.remindly.anakhsoft.com
- Check for valid SSL certificate (Let's Encrypt)
- Should show no browser warnings

## Common Commands

```bash
# View application logs
kamal logs

# Restart application
kamal app restart

# SSH into container
kamal shell

# Database console
kamal dbc

# Rollback to previous version
kamal rollback

# Remove everything (DANGEROUS!)
kamal remove
```

## Troubleshooting

### SSL Certificate Issues
```bash
# Check Traefik logs
kamal traefik logs

# Restart Traefik
kamal traefik restart

# Verify DNS is pointing correctly
dig api.remindly.anakhsoft.com
```

### Application Won't Start
```bash
# Check logs for errors
kamal app logs --tail 100

# Common issues:
# - Missing RAILS_MASTER_KEY
# - Database migration needed
# - Port conflicts
```

### Registry Authentication Failed
```bash
# Test Docker login locally
docker login registry.digitalocean.com/anakhsoft -u navjeetc

# Verify KAMAL_REGISTRY_PASSWORD in .kamal/secrets
# Make sure token has registry read/write permissions
```

### Database Issues
```bash
# Check database file
kamal app exec "ls -lh db/"

# Run migrations
kamal app exec "bin/rails db:migrate"

# Check database console
kamal dbc
```

## Environment Variables

Current production environment variables (from deploy.yml):
- `RAILS_SERVE_STATIC_FILES=true` - Serve assets directly
- `RAILS_LOG_TO_STDOUT=true` - Log to stdout for Docker
- `RAILS_ENV=production` - Production mode
- `RAILS_MASTER_KEY` - From secrets file

## Monitoring

### Basic Health Checks
```bash
# Application status
kamal app details

# Recent logs
kamal logs --tail 50

# Container resource usage
kamal app exec "ps aux"

# Update user names from their email addresses, using rake task
kamal app exec "bin/rails users:populate_names_from_email"

```

### Set Up External Monitoring
Consider using:
- UptimeRobot (free tier available)
- Pingdom
- StatusCake

Monitor endpoint: `https://api.remindly.anakhsoft.com/health`

## Backup Strategy

### SQLite Database Backup
```bash
# Create backup
kamal app exec "sqlite3 /rails/db/production.sqlite3 '.backup /rails/storage/backup-$(date +%Y%m%d).db'"

# Download backup from VPS
scp navjeetc@YOUR_VPS_IP:/path/to/docker/volume/storage/backup-*.db ./backups/
```

### Automated Backups
Set up a cron job on VPS to backup database daily.

## Security Notes

- ✅ `.kamal/secrets` is in `.gitignore`
- ✅ Using DigitalOcean Container Registry (private)
- ✅ SSL enabled via Let's Encrypt
- ✅ Running as non-root user in container
- ✅ Using SSH key authentication (user: navjeetc)

## Cost Estimate

Based on your gifter app setup:
- VPS: ~$12-24/month (depending on size)
- Container Registry: Included with DO account
- Domain: ~$12/year (already have anakhsoft.com)
- SSL: Free (Let's Encrypt)

**Total: ~$12-24/month**

## Next Steps After Deployment

1. [ ] Test all API endpoints
2. [ ] Set up monitoring/uptime checks
3. [ ] Configure automated backups
4. [ ] Update macOS app to use production API URL
5. [ ] Test magic link emails in production
6. [ ] Set up error tracking (Sentry, Rollbar, etc.)

## Support Resources

- Kamal Docs: https://kamal-deploy.org
- Your gifter app: `/Users/navjeetc/dev/ror_apps/gifter`
- DigitalOcean Docs: https://docs.digitalocean.com
