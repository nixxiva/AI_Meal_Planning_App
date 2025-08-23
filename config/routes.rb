Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      devise_for :users,
                 path: '',
                 path_names: {
                   sign_in: 'login',
                   sign_out: 'logout',
                   registration: 'signup'
                 },
                 controllers: {
                   sessions: 'api/v1/users/sessions',
                   registrations: 'api/v1/users/registrations',
                   confirmations: 'api/v1/users/confirmations'
                 }
      
      resources :users, only: [:show] do
        #user_profile route
        resource :user_profile, only: [:show, :update, :destroy], controller: 'users/user_profiles'
        
        resources :pantry_items, only: [:index, :create, :update, :destroy]
        resources :meal_plans, only: [:index, :create]
        resources :meal_logs, only: [:index, :create]
        resources :disliked_ingredients, only: [:create, :destroy]
        resources :allergies, only: [:index, :create, :destroy]
        resources :dietary_preferences, only: [:index, :create, :destroy]
      end
      
      # Non-nested resources (not specific to a user) will adjust if need under user
      resources :recipes, only: [:index, :show, :create] do
        member do
          post :rate
          post :adjust
        end
      end
    end
  end
end
