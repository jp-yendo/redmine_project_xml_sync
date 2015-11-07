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
      message, @title, @usermapping, @assignments, @tasks, root_ids = ProjectXmlImport.import(@project, @upload_path)
      redirect_to :action => 'import_results', :id => @project, :root_ids => root_ids
    else
      upload  = params[:uploaded_file]
      @upload_path = upload.path
      Rails.logger.info "upload xml file: #{upload.class.name}: #{upload.inspect} : #{upload.original_filename} : uploaded_path: #{@upload_path}"
      message, @title, @usermapping, @assignments, @tasks = ProjectXmlImport.analyze(@project, @upload_path)
    end

    show_message(message)
  end

  def import_results
    @root_ids = params[:root_ids]
    @import_root_issues = Issue.where(:id => @root_ids, :parent_id => nil)
    @import_issues = Issue.where(:root_id => @root_ids)
  end

  def export
    xml, name = ProjectXmlExport.generate_xml(@project)
    send_data xml, :filename => name, :disposition => :attachment
  end
  
private
  def find_project
    @project = Project.find(params[:id])
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