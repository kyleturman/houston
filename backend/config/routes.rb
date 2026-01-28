Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "admin/dashboard#index"

  # Plaid OAuth redirect (for bank OAuth flows like Chase)
  get "plaid-oauth", to: "plaid_oauth#callback"

  # Admin Dashboard
  namespace :admin do
    get '/', to: 'dashboard#index', as: 'dashboard'
    get 'signin', to: 'signin#new', as: 'signin'
    post 'signin', to: 'signin#create'
    delete 'signout', to: 'signin#destroy', as: 'signout'
    post 'create_user', to: 'dashboard#create_user', as: 'create_user'
    post 'create_user_with_token', to: 'dashboard#create_user_with_token', as: 'create_user_with_token'
    post 'send_link', to: 'dashboard#send_link', as: 'send_link'
    post 'revoke_device', to: 'dashboard#revoke_device', as: 'revoke_device'
    post 'deactivate_user', to: 'dashboard#deactivate_user', as: 'deactivate_user'
    post 'reactivate_user', to: 'dashboard#reactivate_user', as: 'reactivate_user'
    post 'create_invite_token', to: 'dashboard#create_invite_token', as: 'create_invite_token'
    post 'revoke_invite_token', to: 'dashboard#revoke_invite_token', as: 'revoke_invite_token'
  end

  # Sidekiq Web UI (development only for now, add auth for production)
  if Rails.env.development?
    require 'sidekiq/web'
    require 'sidekiq/cron/web'
    mount Sidekiq::Web => '/admin/sidekiq'
  end

  # Web-based authentication (not under /api)
  scope :auth do
    get "signin", to: "auth/signin#show"
  end

  scope :api do
    get  "ping", to: "ping#show"

    scope :auth do
      # Magic sign-in links (passwordless auth)
      post "magic_links/claim", to: "auth/magic_links#claim" # exchange token for device token

      # Invite token auth (for TestFlight review and self-hosted users without email)
      post "invite_tokens/claim", to: "auth/invite_tokens#claim"

      # Request new sign-in link (for remembered users re-signing in)
      post "request_signin", to: "auth/signin_request#create"

      # Account status (check if user exists)
      post "account_status", to: "auth/accounts#status"

      # Sessions (logout is a no-op for JWT but kept for API parity)
      delete "sessions", to: "auth/sessions#destroy"

      # Token refresh
      post "refresh", to: "auth/token_refresh#create"
    end

    # Health monitoring endpoints
    scope module: 'api' do
      get 'health', to: 'health#show'
      get 'health/streams', to: 'health#streams'
      get 'health/system', to: 'health#system'
    end

    # Server capabilities (for self-hosted detection)
    scope module: 'api' do
      get 'capabilities', to: 'capabilities#index'
    end

    # Background refresh polling (for local notifications)
    scope module: 'api' do
      get 'updates/since/:timestamp', to: 'updates#since'
    end

    # Goals and Notes API (user-scoped in controllers)
    scope module: 'api' do
      # Goal creation chat (stateless)
      namespace :goal_creation_chat do
        get :stream
        post :message
      end

      # Global stream for user-wide events (notes, tasks, goals)
      get 'stream/global', to: 'global_stream#stream'

      resources :goals do
        resources :notes, only: [:index, :create]
        # Tasks under a goal
        resources :agent_tasks, only: [:index]
        # Maintenance: clear agent-related state for a goal (thread, tasks, agent instances, queued jobs)
        collection do
          post :reorder
        end
        member do
          post :agent_reset
        end
        # Thread endpoints (new)
        resources :thread_messages, only: [:index, :create], path: 'thread/messages', controller: 'thread_messages' do
          collection do
            get :stream
          end
        end
        # Agent history sessions
        resources :agent_histories, only: [:index, :show, :destroy] do
          collection do
            get :current
            delete :current, action: :reset_current
          end
        end
      end
      resources :agent_tasks, only: [:show] do
        member do
          post :retry
        end
        # Thread endpoints for tasks (new)
        resources :thread_messages, only: [:index, :create], path: 'thread/messages', controller: 'thread_messages' do
          collection do
            get :stream
          end
        end
      end
      resources :notes, only: [:index, :show, :update, :destroy, :create] do
        member do
          post :retry_processing
          post :ignore_processing
        end
      end

      # User Agent endpoints (home assistant)
      resource :user_agent, only: [:show, :update], controller: 'user_agent' do
        post :reset, on: :member
        resources :thread_messages, only: [:index, :create], path: 'thread/messages', controller: 'thread_messages' do
          collection do
            get :stream
          end
        end
        # Agent history sessions
        resources :agent_histories, only: [:index, :show, :destroy] do
          collection do
            get :current
            delete :current, action: :reset_current
          end
        end
      end

      # Standalone thread message actions (retry/dismiss error messages)
      resources :thread_messages, only: [:destroy], controller: 'thread_messages' do
        member do
          post :retry
        end
      end

      # User profile endpoints
      resource :user_profile, path: 'user/profile', only: [:show, :update], controller: 'user_profile'

      # Shortcuts/Siri/App Intents (user auth required)
      namespace :shortcuts do
        post :agent_query
      end

      # Feed endpoints
      namespace :feed do
        get :current
        get :history
        get :schedule
        patch :schedule, action: :update_schedule
        post :generate_insights  # TEMP: Manual trigger for testing
      end

      # Agent activity tracking
      resources :agent_activities, only: [:index, :show]

      # MCP endpoints - unified for local and remote servers
      namespace :mcp do
        # Generic MCP server connection endpoints
        # Allow dots in server names (e.g., "last.fm") by constraining format
        scope ':server_name', constraints: { server_name: /[^\/]+/ } do
          post 'auth/initiate', to: 'connections#initiate'
          post 'auth/exchange', to: 'connections#exchange'
          get 'connections', to: 'connections#index'
          get 'status', to: 'connections#status'
        end

        delete 'connections/:id', to: 'connections#destroy', constraints: { id: /[^\/]+/ }

        # URL-based servers (like Zapier) where secret is in URL
        post 'url_servers', to: 'connections#create_from_url'
        get 'url_servers/:server_name', to: 'connections#url_server_status', constraints: { server_name: /[^\/]+/ }
        delete 'url_servers/:server_name', to: 'connections#destroy_url_server', constraints: { server_name: /[^\/]+/ }

        # Legacy remote OAuth endpoints (kept for backward compat)
        get 'oauth/authorize', to: 'oauth#authorize'
        get 'oauth/callback', to: 'oauth#callback'
        post 'oauth/refresh', to: 'oauth#refresh'
        delete 'oauth/revoke', to: 'oauth#revoke'

        # Allow dots in server IDs (e.g., "remote_last.fm") by constraining id format
        resources :servers, only: [:index, :show], constraints: { id: /[^\/]+/ } do
          member do
            post :connect
            delete :disconnect
          end
        end
      end
    end
  end
end
