TabularImporter::Engine.routes.draw do
  resources :imports, path: "", only: %i[index new create show] do
    member do
      patch :update_mapping
      post :process, action: :start_processing
      post :retry_import
      get :progress
    end
  end

  root to: "imports#index"
end
