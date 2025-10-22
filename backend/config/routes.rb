Rails.application.routes.draw do
  # Root - redirect to dashboard
  root "dashboard#index"
  
  # Web Client (Voice Announcements)
  get "client", to: redirect("/client/index.html", status: 302)
  
  # Web authentication
  get  "login",              to: "sessions#new", as: :login
  post "login/magic",        to: "sessions#request_magic_link", as: :request_magic_link
  get  "login/verify",       to: "sessions#verify_magic_link", as: :verify_magic_link
  get  "dev_login",          to: "sessions#dev_login", as: :dev_login
  delete "logout",           to: "sessions#destroy", as: :logout
  
  # Magic link authentication (API)
  get  "magic/request",      to: "magic#request_link"
  get  "magic/verify",       to: "magic#verify"
  get  "magic/dev_exchange", to: "magic#dev_exchange"
  
  # Admin panel
  namespace :admin do
    resources :users, only: [:index] do
      member do
        patch :update_role
      end
    end
  end
  
  # Web dashboard
  get  "dashboard",          to: "dashboard#index", as: :dashboard
  get  "profile",            to: "dashboard#profile", as: :profile
  patch "profile",           to: "dashboard#update_profile"
  get  "dashboard/pair",     to: "dashboard#pair", as: :pair_dashboard
  post "dashboard/pair",     to: "dashboard#process_pair"
  get  "dashboard/generate", to: "dashboard#generate_token", as: :generate_token_dashboard
  get  "dashboard/senior/:id", to: "dashboard#senior", as: :senior_dashboard
  get  "dashboard/senior/:senior_id/reminder/new", to: "dashboard#new_reminder", as: :new_reminder_dashboard
  post "dashboard/senior/:senior_id/reminder", to: "dashboard#create_reminder", as: :create_reminder_dashboard
  get  "dashboard/senior/:senior_id/reminder/:reminder_id/edit", to: "dashboard#edit_reminder", as: :edit_reminder_dashboard
  patch "dashboard/senior/:senior_id/reminder/:reminder_id", to: "dashboard#update_reminder", as: :update_reminder_dashboard
  delete "dashboard/senior/:senior_id/reminder/:reminder_id", to: "dashboard#delete_reminder", as: :delete_reminder_dashboard
  delete "dashboard/unlink/:id", to: "dashboard#unlink", as: :unlink_dashboard
  get  "dashboard/senior/:senior_id/invite_caregiver", to: "dashboard#invite_caregiver", as: :invite_caregiver_dashboard
  post "dashboard/senior/:senior_id/invite_caregiver", to: "dashboard#process_invite_caregiver"
  
  resources :reminders do
    collection do
      get :today
      delete :bulk_destroy
    end
  end
  
  resources :acknowledgements, only: [:create] do
    collection do
      post :snooze
    end
  end
  
  # Caregiver pairing
  resources :caregiver_links, only: [:index, :destroy] do
    collection do
      post :generate_token
      post :pair
    end
  end
  
  # Caregiver dashboard
  get 'caregiver_dashboard/:senior_id/activity', to: 'caregiver_dashboard#activity'
  get 'caregiver_dashboard/:senior_id/today', to: 'caregiver_dashboard#today'
  get 'caregiver_dashboard/:senior_id/missed_count', to: 'caregiver_dashboard#missed_count'
  
  # Tasks (web interface)
  resources :seniors, only: [] do
    resources :tasks do
      member do
        post :complete
        post :assign
      end
      resources :comments, controller: 'task_comments', only: [:create, :destroy]
    end
  end
  
  # API routes
  namespace :api do
    resources :tasks do
      member do
        post :assign
        post :claim
      end
      resources :comments, controller: 'task_comments', only: [:index, :create, :destroy]
    end
    
    resources :availability, controller: 'caregiver_availabilities', only: [:index, :create, :update, :destroy]
  end
  
  get "up" => "rails/health#show", as: :rails_health_check
end
