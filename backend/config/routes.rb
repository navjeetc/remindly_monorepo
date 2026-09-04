Rails.application.routes.draw do
  # Root - marketing page for logged-out visitors, dashboard for signed-in users.
  # Was dashboard#index behind authenticate!, which meant / redirected to /login
  # and the site had no indexable homepage at all.
  root "pages#home"

  # Web authentication
  get  "login",              to: "sessions#new", as: :login
  post "login/magic",        to: "sessions#request_magic_link", as: :request_magic_link
  get  "login/verify",       to: "sessions#verify_magic_link", as: :verify_magic_link
  get  "dev_login",          to: "sessions#dev_login", as: :dev_login
  delete "logout",           to: "sessions#destroy", as: :logout

  # Magic link authentication (API)
  get  "magic/request",      to: "magic#request_link"
  get  "magic/verify",       to: "magic#verify"  # Keep GET for email links
  post "magic/verify",       to: "magic#verify"  # POST for better security
  get  "magic/dev_exchange", to: "magic#dev_exchange"

  # Admin panel
  namespace :admin do
    resources :users, only: [ :index ] do
      member do
        patch :update_role
      end
    end
    resources :audit_logs, only: [ :index, :show ]
    resources :traffic, only: [ :index ]
  end

  # Public pages (no authentication required)
  get  "how_to",             to: "pages#how_to", as: :how_to
  get  "faq",                to: "pages#faq", as: :faq
  get  "routine_sheet",      to: "pages#routine_sheet", as: :routine_sheet
  get  "caregiver_checklist", to: "pages#caregiver_checklist", as: :caregiver_checklist
  get  "privacy",            to: "pages#privacy", as: :privacy
  get  "terms",              to: "pages#terms", as: :terms

  # Telnyx Call Control webhooks (public, token-secured)
  post "telnyx/webhooks",    to: "telnyx_webhooks#receive"

  # Hyphens, unlike every other path here, because this one exists to be landed
  # on from a search and the words in it are the search. The route helper keeps
  # the underscored Ruby name.
  get  "reminder-app-for-elderly-parents",
       to: "pages#reminder_app_for_elderly_parents",
       as: :reminder_app_for_elderly_parents

  # Blog. Posts are Markdown files in content/posts, so there is nothing to
  # create or edit over HTTP — only these two reads.
  get  "blog",               to: "posts#index", as: :blog
  get  "blog/:slug",         to: "posts#show", as: :post

  # Mailing list. Create only: unsubscribing is a reply to the email, which for
  # a list this size is a person reading it rather than a link that has to stay
  # working forever.
  resources :subscribers, only: [ :create ]

  # Matches /sitemap.xml — the trailing ".xml" is parsed as the format segment,
  # which is the path robots.txt points crawlers at.
  get  "sitemap",            to: "pages#sitemap", as: :sitemap, defaults: { format: "xml" }

  # Web dashboard
  get  "dashboard",          to: "dashboard#index", as: :dashboard
  # A reminder link. Short on purpose: this is read aloud down a telephone and
  # typed on a tablet by somebody whose eyesight is part of why you are setting
  # this up. The token is exchanged for a cookie and dropped from the address
  # bar on the redirect.
  get  "r/:token", to: "reminder_links#show", as: :reminder_link

  get  "voice_reminders",    to: "voice_reminders#show", as: :voice_reminders
  get  "voice_reminders/today", to: "voice_reminders#today", as: :voice_reminders_today
  get  "contact",            to: "dashboard#contact", as: :contact
  post "contact",            to: "dashboard#submit_contact"
  get  "profile",            to: "dashboard#profile", as: :profile
  patch "profile",           to: "dashboard#update_profile"
  patch "select_role",       to: "dashboard#select_role", as: :select_role
  get  "dashboard/pair",     to: "dashboard#pair", as: :pair_dashboard
  post "dashboard/pair",     to: "dashboard#process_pair"
  get  "dashboard/generate", to: "dashboard#generate_token", as: :generate_token_dashboard
  get  "dashboard/senior/:id", to: "dashboard#senior", as: :senior_dashboard

  # Proposing a number and asking its owner whether they agree to be telephoned.
  # Two separate actions because they are two separate acts: writing down a
  # number commits nobody to anything, and only the second one makes a phone
  # ring. Nothing here can grant consent — that is the verification call's alone.
  patch "dashboard/senior/:senior_id/phone", to: "dashboard#update_phone", as: :senior_phone
  patch "dashboard/senior/:senior_id/spoken_language", to: "dashboard#update_spoken_language", as: :senior_spoken_language
  post  "dashboard/senior/:senior_id/verify_phone", to: "dashboard#verify_phone", as: :verify_senior_phone

  # The device link a care receiver bookmarks. Minting is a write and revoking
  # is a write, so both are POSTs behind the same manage permission the phone
  # panel uses — a view-only caregiver can see whether the tablet is working and
  # change nothing about it.
  post  "dashboard/senior/:senior_id/reminder_link", to: "dashboard#create_reminder_link", as: :senior_reminder_link
  post  "dashboard/senior/:senior_id/reminder_link/:id/revoke", to: "dashboard#revoke_reminder_link", as: :revoke_senior_reminder_link
  get  "dashboard/senior/:senior_id/reminder/new", to: "dashboard#new_reminder", as: :new_reminder_dashboard
  post "dashboard/senior/:senior_id/reminder", to: "dashboard#create_reminder", as: :create_reminder_dashboard
  get  "dashboard/senior/:senior_id/reminder/:reminder_id/edit", to: "dashboard#edit_reminder", as: :edit_reminder_dashboard
  patch "dashboard/senior/:senior_id/reminder/:reminder_id", to: "dashboard#update_reminder", as: :update_reminder_dashboard
  delete "dashboard/senior/:senior_id/reminder/:reminder_id", to: "dashboard#delete_reminder", as: :delete_reminder_dashboard
  delete "dashboard/unlink/:id", to: "dashboard#unlink", as: :unlink_dashboard
  patch  "dashboard/caregivers/:id/permission", to: "dashboard#update_caregiver_permission", as: :caregiver_permission_dashboard
  get  "dashboard/senior/:senior_id/invite_caregiver", to: "dashboard#invite_caregiver", as: :invite_caregiver_dashboard
  post "dashboard/senior/:senior_id/invite_caregiver", to: "dashboard#process_invite_caregiver"

  resources :reminders do
    collection do
      get :today
      get :profile
      delete :bulk_destroy
    end
  end

  # The standalone voice client at /client/ was retired — /voice_reminders
  # superseded it and it served no traffic. Kept as a redirect rather than a 404
  # so any bookmark or old magic link still lands somewhere useful.
  #
  # Magic links in already-sent emails look like /client/?token=... and stay valid
  # for 30 minutes. A plain redirect would drop the token, land the user
  # unauthenticated on /voice_reminders and bounce them to the login page — the
  # link would appear broken. Token-bearing requests go through /login/verify
  # instead, which is where those links point from now on anyway.
  retired_client = lambda do |_params, request|
    token = request.params[:token]

    if token.present?
      "/login/verify?#{{ token: token, next: 'voice_reminders' }.to_query}"
    else
      "/voice_reminders"
    end
  end

  get "client", to: redirect(&retired_client)
  get "client/*rest", to: redirect(&retired_client)

  resources :acknowledgements, only: [ :create ] do
    collection do
      post :snooze
    end
  end

  # Caregiver pairing
  resources :caregiver_links, only: [ :index, :destroy ] do
    collection do
      post :generate_token
      post :pair
    end
  end

  # Caregiver dashboard
  get "caregiver_dashboard/:senior_id/activity", to: "caregiver_dashboard#activity"
  get "caregiver_dashboard/:senior_id/today", to: "caregiver_dashboard#today"
  get "caregiver_dashboard/:senior_id/missed_count", to: "caregiver_dashboard#missed_count"

  # Tasks (web interface)
  resources :seniors, only: [] do
    resources :time_blocks, except: [ :show ]

    resources :tasks do
      member do
        post :complete
        post :assign
        post :unassign
      end
      resources :comments, controller: "task_comments", only: [ :create, :destroy ]
    end

    # Scheduling integrations
    resources :scheduling_integrations, only: [ :index, :new, :create ]
  end

  # Scheduling integrations (not scoped to senior)
  resources :scheduling_integrations, only: [ :show, :edit, :update, :destroy ] do
    member do
      post :sync
    end
    collection do
      post :verify
    end
  end

  # Native scheduling (feature flagged)
  resources :caregiver_availabilities, only: [ :index, :new, :create, :edit, :update, :destroy ] do
    collection do
      get :bulk_new
      post :bulk_create
    end
  end

  # Senior coverage view for caregivers
  resources :seniors, only: [] do
    resource :coverage, only: [ :show ], controller: "senior_coverage"
  end

  # Notifications
  resources :notifications, only: [ :index ] do
    member do
      post :mark_read
    end
    collection do
      post :mark_all_read
    end
  end

  # DEV ONLY: Quick user switching and testing
  if Rails.env.development?
    get "/dev/switch_user", to: "dev#switch_user"
    post "/dev/trigger_coverage_check", to: "dev#trigger_coverage_check", as: :trigger_coverage_check_dev
  end

  # There is no /api namespace. One existed from the client-server era and was
  # removed in #120 — every controller in it raised before running, and nothing
  # ever called it. The macOS client talks to the routes below and to
  # /reminders and /acknowledgements, not to a versioned API.

  # Version endpoint
  get "version", to: "application#version"

  get "up" => "rails/health#show", as: :rails_health_check
end
