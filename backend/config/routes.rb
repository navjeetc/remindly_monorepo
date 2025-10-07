Rails.application.routes.draw do
  get  "magic/request",      to: "magic#request_link"
  get  "magic/verify",       to: "magic#verify"
  get  "magic/dev_exchange", to: "magic#dev_exchange"
  resources :reminders do
    collection do
      get :today
    end
  end
  resources :acknowledgements, only: [:create] do
    collection do
      post :snooze
    end
  end
  get "up" => "rails/health#show", as: :rails_health_check
end
