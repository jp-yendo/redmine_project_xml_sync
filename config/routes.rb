resources :projects do
  resource :project_xml_sync, :only => [:new, :create], :controller => :project_xml_sync do
    get :export
    post :analyze
  end
end
