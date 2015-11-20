MultipleIssuesForUniqueValue = Class.new(Exception)
NoIssueForUniqueValue = Class.new(Exception)

class Journal < ActiveRecord::Base
  def empty?(*args)
    (details.empty? && notes.blank?)
  end
end

class ProjectXmlSyncController < ApplicationController
  unloadable

  before_filter :find_project, only: [:index, :analyze, :import_results, :export, :csv_import_match, :csv_import_results, :csv_export]
#  before_filter :find_project, :get_plugin_settings, only: [:index, :analyze, :import_results, :export]
  before_filter :authorize, :except => :analyze
#  before_filter :get_import_settings, :only => [:index, :analyze, :import_results]
#  before_filter :get_export_settings, :only => [:index, :export]

  def index
#    flash.clear
  end

  def analyze
    if params[:do_import].nil?
      do_import = 'false'
    else
      do_import = params[:do_import]
    end
    
    if do_import == 'true'
      @upload_path = params[:upload_path]
      Rails.logger.info "start import from #{@upload_path}"
      @title, @usermapping, @assignments, @tasks, root_ids = ProjectXmlImport.import(@project, @upload_path)
      unless ProjectXmlImport.message[:error].present?
        redirect_to :action => 'import_results', :id => @project, :root_ids => root_ids
      end
    else
      upload  = params[:uploaded_file]
      @upload_path = upload.path
      Rails.logger.info "upload xml file: #{upload.class.name}: #{upload.inspect} : #{upload.original_filename} : uploaded_path: #{@upload_path}"
      @title, @usermapping, @assignments, @tasks = ProjectXmlImport.analyze(@project, @upload_path)
    end

    show_message(ProjectXmlImport.message)
    if ProjectXmlImport.message[:error].present?
      redirect_to :action => 'index', :id => @project
    end
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

  def csv_import_match
    @import_csv_params = Hash.new
    @import_csv_params[:csv_import_splitter] = params[:csv_import_splitter]
    if @import_csv_params[:csv_import_splitter].nil? || @import_csv_params[:csv_import_splitter].blank?
      @import_csv_params[:csv_import_splitter] = ","
    end
    @import_csv_params[:csv_import_wrapper] = params[:csv_import_wrapper]
    if @import_csv_params[:csv_import_wrapper].nil? || @import_csv_params[:csv_import_wrapper].blank?
      @import_csv_params[:csv_import_wrapper] = "\""
    end
    @import_csv_params[:csv_import_encoding] = params[:csv_import_encoding]
    @import_csv_params[:created] = Time.new
    @import_csv_params[:csv_file_path] = params[:csv_import_file].path unless params[:csv_import_file].blank?
    @import_csv_params[:csv_original_filename] = params[:csv_import_file].original_filename unless params[:csv_import_file].blank?

    @import_timestamp = @import_csv_params[:created].strftime("%Y-%m-%d %H:%M:%S")

    @headers, @attrs, @samples = ProjectCsvImport.match(@project, @import_csv_params)
    show_message(ProjectCsvImport.message)
    if ProjectCsvImport.message[:error].present?
      redirect_to :action => 'index', :id => @project
    end
  end

  def csv_import_results
    @import_csv_params = params[:import_params]
    @messages, @handle_count, @affect_projects_issues, @failed_count, @headers, @failed_issues = ProjectCsvImport.result(@project, @import_csv_params, params)
    show_message(ProjectCsvImport.message)
  end
  
  def csv_export
    begin
      csv, name = ProjectCsvExport.generate_simple_csv(@project)
      case params[:csv_export_encoding]
      when "S"
        csv = csv.encode(Encoding::SJIS)
      end
      send_data csv, :filename => name, :disposition => :attachment
    rescue Exception => ex
      
    end
    show_message(ProjectCsvExport.message)
    if ProjectCsvExport.message[:error].present?
      redirect_to :action => 'index', :id => @project
    end
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