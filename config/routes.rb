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

      resources :users, only: [] do
        resource :user_profile, only: [:show, :update, :destroy], controller: 'users/user_profiles'
      end
    end
  end
end
