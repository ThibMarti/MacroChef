Rails.application.routes.draw do
  get "messages/create"
  get "chats/show"
  get "preferences/new"
  get "preferences/create"
  devise_for :users
  root to: "pages#home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  get "meal_plans", to: "meal_plans#index", as: :meal_plans
  resources :preferences, only: [:new, :create]

  resources :chats, only: [:index, :show] do
    resources :messages, only: [:create] do
      member do
        patch :swap_meal
        patch :update_ingredient
        post :add_ingredient
        delete :remove_ingredient
      end
    end
  end

  resources :recipes, only: [:index, :new, :create, :show, :edit, :update] do
    member do
      post :toggle_favorite
    end
  end
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
