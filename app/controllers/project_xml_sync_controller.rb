class ProjectXmlSyncController < ApplicationController
  unloadable

  before_filter :find_project, only: [:index, :analyze, :import_results, :export]
#  before_filter :find_project, :get_plugin_settings, only: [:index, :analyze, :import_results, :export]
  before_filter :authorize, :except => :analyze
#  before_filter :get_import_settings, :only => [:index, :analyze, :import_results]
#  before_filter :get_export_settings, :only => [:index, :export]

  def index
    flash.clear
  end

  def analyze
    flash.clear

    if params[:do_import].nil?
      do_import = 'false'
    else
      do_import = params[:do_import]
    end
    
    if do_import == 'true'
      @upload_path = params[:upload_path]
      Rails.logger.info "start import from #{@upload_path}"
      message, @title, @usermapping, @assignments, @tasks, root_task_id = ProjectXmlImport.import(@project, @upload_path)
      redirect_to :action => 'import_results', :project_id => @project, :root_task => root_task_id
    else
      upload  = params[:uploaded_file]
      @upload_path = upload.path
      Rails.logger.info "upload xml file: #{upload.class.name}: #{upload.inspect} : #{upload.original_filename} : uploaded_path: #{@upload_path}"
      message, @title, @usermapping, @assignments, @tasks = ProjectXmlImport.analyze(@project, @upload_path)
    end

    show_message(message)
  end

  def import_results

  end

  def export
    begin
      xml, name = ProjectXmlExport.generate_xml
      send_data xml, :filename => name, :disposition => :attachment
    rescue => error
      flash[:error] = "export task error: " + error.to_s
      Rails.logger.debug "DEBUG: export task error: #{ error }"
      redirect_to :action => "index"
    end
  end
  
private
  def find_project
    @project = Project.find(params[:project_id])
  end
  
  def show_message(message)
    if message.nil?
      return
    end
    if !message[:error].nil?
      flash[:error] = message[:error]
    end
    if !message[:warning].nil?
      flash[:warning] = message[:warning]
    end
    if !message[:notice].nil?
      flash[:notice] = message[:notice]
    end
  end
end