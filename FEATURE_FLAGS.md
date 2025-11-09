# Feature Flags

Feature flags allow you to enable/disable features without code changes. This is useful for:
- Rolling out features gradually
- A/B testing
- Disabling features in production
- Development/testing

## Available Features

### Native Scheduling
**Key:** `:native_scheduling`  
**Default:** `false` (disabled)  
**Environment Variable:** `ENABLE_NATIVE_SCHEDULING`

Built-in appointment scheduling system. When enabled:
- Caregivers can set their availability
- Seniors/family can book appointments
- Calendar view for appointments
- Email notifications

### External Scheduling Integrations
**Key:** `:external_scheduling`  
**Default:** `true` (enabled)  
**Environment Variable:** `ENABLE_EXTERNAL_SCHEDULING`

Integration with external scheduling services (Acuity, Calendly). When enabled:
- Connect Acuity Scheduling accounts
- Sync appointments from external services
- View external appointments in Remindly

## Usage

### In Code

```ruby
# Check if a feature is enabled
if FeatureFlag.enabled?(:native_scheduling)
  # Show native scheduling UI
end

# Check if a feature is disabled
if FeatureFlag.disabled?(:external_scheduling)
  # Hide external integrations
end
```

### In Views

```erb
<% if FeatureFlag.enabled?(:native_scheduling) %>
  <%= link_to "My Availability", caregiver_availabilities_path %>
<% end %>
```

### In Controllers

```ruby
class MyController < ApplicationController
  before_action :check_feature_enabled!
  
  private
  
  def check_feature_enabled!
    unless FeatureFlag.enabled?(:native_scheduling)
      redirect_to dashboard_path, alert: "Feature not enabled"
    end
  end
end
```

## Configuration

### Development

Set environment variables in `.env`:

```bash
# Enable native scheduling
ENABLE_NATIVE_SCHEDULING=true

# Disable external scheduling
ENABLE_EXTERNAL_SCHEDULING=false
```

### Production

Set environment variables in your deployment:

**Kamal (config/deploy.yml):**
```yaml
env:
  clear:
    ENABLE_NATIVE_SCHEDULING: "true"
    ENABLE_EXTERNAL_SCHEDULING: "true"
```

**Heroku:**
```bash
heroku config:set ENABLE_NATIVE_SCHEDULING=true
```

**Docker:**
```bash
docker run -e ENABLE_NATIVE_SCHEDULING=true ...
```

### Testing

Enable/disable features in tests:

```ruby
# In RSpec
before do
  FeatureFlag.enable!(:native_scheduling)
end

after do
  FeatureFlag.disable!(:native_scheduling)
end

# Or use environment variables
it "shows availability when enabled" do
  ENV["ENABLE_NATIVE_SCHEDULING"] = "true"
  # test code
end
```

## Adding New Features

1. **Define the feature** in `app/models/feature_flag.rb`:

```ruby
FEATURES = {
  my_new_feature: {
    name: "My New Feature",
    description: "Description of what this does",
    default: false,
    env_var: "ENABLE_MY_NEW_FEATURE"
  }
}.freeze
```

2. **Use the feature flag** in your code:

```ruby
if FeatureFlag.enabled?(:my_new_feature)
  # Feature code
end
```

3. **Document it** in this file

## Best Practices

1. **Default to disabled** for new features
2. **Use descriptive names** for features
3. **Document the feature** in this file
4. **Clean up old flags** after features are stable
5. **Test both enabled and disabled states**
6. **Use environment variables** for production control

## Migration Path

When a feature is stable and ready for all users:

1. Change `default: true` in the feature definition
2. Remove feature flag checks from code
3. Remove the feature from `FEATURES` hash
4. Update documentation

## Current Feature Status

| Feature | Default | Status |
|---------|---------|--------|
| Native Scheduling | Disabled | 🚧 In Development |
| External Scheduling | Enabled | ✅ Production Ready |

---

**Last Updated:** November 9, 2025
