require 'csv'
require 'tempfile'
class ImportwizardController < ApplicationController
  before_filter :login_required

  #sets t@entity
  before_filter :check_all_ids 

  #step 1
  def index
    @entity = Entity.find params[:id]
  end
  
  #step 2
  def link_fields
    redirect_to :action => "index", :id => params[:id]  and return if params["file_to_import"]==""
    #save file in user's tmp zone
    f=Tempfile.new(%{#{@entity.name}}, import_temp_dir ) 
    f.print(params["file_to_import"].read) 
    f.close
    csv = nil
    begin
      csv = CSV::parse(File.read(f.path))
    rescue CSV::IllegalFormatError => e
      flash["error"]=I18n.t('import_wizard.csv_format_invalid')
      redirect_to :action => "index", :id => params[:id]  and return
    end
    @csv_fields = csv.shift
    @csv_fields.insert(0, "----")
    @entity_fields = @entity.details_hash.keys
    FileUtils.cp(f.path, f.path+".perm")
    session[:file_to_import]=f.path+".perm"
  end

  def import_data
    @entity = Entity.find params[:id]
    @imported_instances=[]
    @invalid_entries=[]
    csv=CSV::parse(File.read(session[:file_to_import]))
    @csv_fields = csv.shift
    @bindings=params[:bindings].inject({}){|acc,i| 
      acc.merge!({ i[0] => @csv_fields.index(i[1]) }) if i[1]!='----' 
      acc
    }

    csv.each do |row| 
      # b[0] is detail
      # b[1] is csv column number
      h = @bindings.inject({}) do |acc,b| 
        acc.merge({b[0] => row[b[1]]}) 
      end
      i, invalid_fields = Entity.instanciate(params[:id], h)
      if i
        @imported_instances.push i.id
      else
        @invalid_entries.push row
      end
      session[:imported_instances]= @imported_instances unless ActionController::Base.session_store==ActionController::Session::CookieStore
    end

  end

  def delete_imported
      @deleted_items = Instance.destroy_all( :id => session[:imported_instances])
      session[:imported_instances]=nil
  end

  private 
  def check_all_ids
    redirect_to :controller => "database" and return false if  params[:id].nil?
    @entity=Entity.find params[:id]
    if @entity.nil? or !user_dbs.include? @entity.database
      flash["error"] = t("madb_entity_not_in_your_dbs")
      redirect_to :controller => "database" and return false
    end
  end

  def import_temp_dir
    dir = "#{RAILS_ROOT}/tmp/#{session["user"].id}/import/#{@entity.id}"
    FileUtils.mkdir_p dir unless File.exists? dir
    return dir
  end
end
