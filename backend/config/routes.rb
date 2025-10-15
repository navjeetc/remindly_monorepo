Rails.application.routes.draw do
  # Root - redirect to dashboard
  root "dashboard#index"
  
  # Web authentication
  get  "login",              to: "sessions#new", as: :login
  get  "dev_login",          to: "sessions#dev_login", as: :dev_login
  delete "logout",           to: "sessions#destroy", as: :logout
  
  # Magic link authentication (API)
  get  "magic/request",      to: "magic#request_link"
  get  "magic/verify",       to: "magic#verify"
  get  "magic/dev_exchange", to: "magic#dev_exchange"
  
  # Web dashboard
  get  "dashboard",          to: "dashboard#index", as: :dashboard
  get  "dashboard/pair",     to: "dashboard#pair", as: :pair_dashboard
  post "dashboard/pair",     to: "dashboard#process_pair"
  get  "dashboard/generate", to: "dashboard#generate_token", as: :generate_token_dashboard
  get  "dashboard/senior/:id", to: "dashboard#senior", as: :senior_dashboard
  delete "dashboard/unlink/:id", to: "dashboard#unlink", as: :unlink_dashboard
  
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
  
  get "up" => "rails/health#show", as: :rails_health_check
end
