RedmineApp::Application.routes.draw do
  match 'project_xml_sync/(:action(/:id))', :controller => 'project_xml_sync', :via => [:get, :post], as: 'project_xml_sync_route'
end