Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "home#index"

  # API routes
  namespace :api do
    namespace :v1 do
      # Authentication routes
      post "auth/signup", to: "auth#signup", as: :signup
      post "auth/login", to: "auth#login", as: :login
      post "auth/refresh", to: "auth#refresh", as: :refresh
      post "auth/logout", to: "auth#logout", as: :logout
      get "auth/me", to: "auth#me", as: :me

      # User routes
      get "users/me", to: "users#me"
      patch "users/me", to: "users#update"

      # Chat routes
      resources :chats, only: [ :create, :index, :destroy ] do
        collection do
          get "sessions"
          delete "sessions/:id", to: "chats#destroy_session"
        end
      end

      # Voice routes
      post "voices/generate", to: "voices#generate"

      # Report routes
      get "report", to: "reports#show"
      post "report/analyze", to: "reports#analyze"
      get "report/weekly", to: "reports#weekly"
      get "report/monthly", to: "reports#monthly"
    end
  end
end
