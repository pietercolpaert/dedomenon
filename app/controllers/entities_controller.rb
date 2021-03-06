################################################################################
#This file is part of Dedomenon.
#
#Dedomenon is free software: you can redistribute it and/or modify
#it under the terms of the GNU Affero General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#Dedomenon is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU Affero General Public License for more details.
#
#You should have received a copy of the GNU Affero General Public License
#along with Dedomenon.  If not, see <http://www.gnu.org/licenses/>.
#
#Copyright 2008 Raphaël Bauduin
################################################################################

# *Description*
#   This class mostly handles the creation of instances and lists
#   various aspects of an entity like the records in it, the relations it has
#   with other entities etc.
#   @json is available for the data exchange with the REST controllers.
#   If further fomrats are supported like XML and YAML, then there would be
#   additional instance variables called 
class EntitiesController < ApplicationController

  require 'entities_module'
  include EntitiesHelpers
  require "time"

  # For all actions, the user must be logged in execpt ones listed in the array.
  before_filter :login_required , :except => ["public_form","public_form_javascript", "apply_edit", "check_detail_value_validity"]
  
  # For the listed actions, check whether the pulic access is available to the 
  # rquested entity.
  before_filter :check_public_access, :only => ["public_form", "public_form_javascript","apply_edit"]
  
  # Checks whether the request contains the requried ids or not. But the actions
  # listed in the array below are not checked for this.
  before_filter :check_all_ids, :except => ["public_form", "apply_edit"]
  
  # For the actions of list, view and add, a return url is set.
  before_filter :set_return_url , :only => ["list", "view", "add"]

  # For cross domain requests, accept handle the OPTIONS request
  before_filter :handle_options_request, :only => ["apply_edit","check_detail_value_validity"] 
  
  layout :determine_layout


  # *Description*
  # Not defined yet, Raphael to instruct on that.
  def public_form_javascript
  end
  
  # *Description*
  #   This function checks whether the requested entity has a public access
  #   form or not. If the user is logged in then the @db is also set to the 
  #   database requested by the user. its also checked whether the database
  #   to which this entity belongs belongs to the current user or not.
  #
  def check_public_access
    

    entity=Entity.find entity_id
    @db= entity.database
    return true if user_dbs.include? entity.database


    if !entity.has_public_form?
        render :text => 'Form inactive or not found', :status => 404 and return false;
    end
    if params["action"]=="apply_edit"
      render :text => '', :status => 404 and return false if params[:instance_id]!="-1"
    end
    
  end
  
  # *Description**
  #   This function sets the @db instance varaible when its provided either
  #   the instance id or entity id.
  #
  def check_all_ids
    # id
    # --
    if params["id"]
      # entity.id
      # ---------
      if ["entities_list","list","add"].include? params["action"]
        begin
          @db = Entity.find(params["id"]).database
        rescue ActiveRecord::RecordNotFound
          flash["error"]=t("madb_error_data_not_found")
          redirect_to :controller => "database" and return false
        end
        if ! user_dbs.include? @db
          flash["error"] = t("madb_entity_not_in_your_dbs")
          redirect_to :controller => "database" and return false
        end
      # instance.id
      # -----------
      elsif ["view", "edit", "apply_edit"].include? params["action"]
        begin
          @db = Instance.find(params["id"]).entity.database
        rescue ActiveRecord::RecordNotFound
          flash["error"]=t("madb_error_data_not_found")
          redirect_to :controller => "database" and return false
        end
        if ! user_dbs.include? @db
          flash["error"] = t("madb_instance_not_in_your_dbs")
          redirect_to :controller => "database" and return false
        end
      end
    end
  end



  # *Description*
  #   Most of the logic is inclined towards views.
  def entities_list
    # sets @sort and @dir
    setup_sort_and_dir
    #FIXME: check we get the params id when editing an instance
    @entity = Entity.find params["id"]

    # If the table(entity) contains no record then error
    if Instance.count(:all, :conditions=> ["entity_id=?",params["id"]])==0
      @list = []
      render and return
    end

    @details = @entity.details_hash
    # list id is of the format "entityname_list like prjects_list"
    @list_id = list_id
    
    if !params["detail_filter"].nil?
      # Div class relates to the class of the table generated by the underlying view
      @div_class = "filtered"
      @separator = "and"   #separator used in page_number method
    else
      @div_class = "unfiltered"
      @separator = "where"
    end
    crosstab_result =  @entity.crosstab_query(:display=> list_display)



    if crosstab_result.nil?
      @list = []
      @paginator = nil
      render and return
    end
    crosstab_query     = crosstab_result[:query]
    @not_in_list_view  = crosstab_result[:not_in_list_view]
    @ordered_fields   = crosstab_result[:ordered_fields]
    @list, @paginator = @entity.get_paginated_list(:filters =>  [crosstab_filter] , :format => params[:format], :highlight => params[:highlight], :default_page => params[list_id+"_page"] || ((params[:startIndex].to_i/list_length).ceil + 1) , :order_by => order_by, :direction => sort_direction, :list_length => list_length )
    
    response.headers["MYOWNDB_highlight"]=params["highlight"].to_s if params["highlight"]



  end
  


  # *Description*
  #   Shows all the instances of the given entity ID.
  #   
  # REST:
  # GET /entities/:entity_id/instances/
  # GET /databases/:database_id/entities/:entity_id/instances
  
  def index
      entities_list()
  end
  
  # *Description*
  #   Lists the records of the given entity.
  # Calls the EntitiesController#entities_list mehtod beneath the surface
  # from the view.
  def list
    @entity = Entity.find params["id"]
    @title = t("madb_list", :vars => { 'entity' => t(@entity.name, :scope => "account")})
    @list_id = list_id
  end

  # *Description*
  #   Shows a single instance
  #   
  # *REST_API*
  #   GET entities/:entity_id/instances/:id
  #   GET databases/:database_id/entities/:entity_id/instances/:id
  # FIXME: For now, we ignore the entity_id and database_id
  # Make to regard them!!!
  def show()
    view()
  end
  
  # *Description*
  #   This basically shows a particular instance.
  #
  def view
    @instance = Instance.find params["id"]
    @entity = @instance.entity :include => [ :entity_details ]
    @title = t("madb_entity_details", :vars => { 'entity' => t(@entity.name, :scope => "account")})
    @crosstab_object = CrosstabObject.find_by_sql(@instance.details_query()+" order by display_order")
  end

  def edit
  	@instance = Instance.find params["id"]
	@entity = @instance.entity
  end
  
  

  # *Description*
  #   Populates the form for the given entity
  #
  def init_add_form
    @entity = Entity.find params["id"]
  end

  # *Description*
  #   Initiates the addition form.
  def add
    init_add_form
    @list_id = list_id
    @title = t("madb_add_and_instance", :vars => { 'entity' => @entity.name})
  end

  # *Description*
  # Saves the given instance or creates a new if it does not exsits.
  # 
  # *Workflow*
  #   Follwilng containers are used:
  #      * ret for representing the sucsuss of the operation
  #      * detail_saved to enlist the fields that saved 
  #      * @invalid_list to enlist the fields that are invalid.
  #   The instance_id is picked from the params and if its negative,
  #   it means we need to create an instance other wise, the instance is picked 
  #   from the database.
  #   For all the fields of the entity to which instance belongs, the params
  #   values are read from params[field_name] 2d array which is array of the
  #   form:
  #     FieldName[number][id|value]
  #   Like if you have a field containing the age then you would have following
  #   setup:
  #     Age[0][value]     # for record 0
  #     Age[1][value]     # for record 1
  #
  #   If the instance is to be created instead of edited, the id fields of the
  #   2d Arry would be empty:
  #   Age[0][id] = ""
  #   Age[0][id] = ""
  #   
  #   But if the instance is to be edited, the id column holds the id of the
  #   Detail value.
  #   
  #   For each of the detail, if the id is not present, then we need to create
  #   the value by pick the datatype of the detail and create a detail_value
  #   object out of it.
  #   But if the id is present then that detail value is picked.
  #   Next step is simply copying the value recieved from the client
  #   to the detail value object and saving it.
  #   See the source code for complete details.
  #

  # *Description*
  #   Applys the editing changes.
  #   internally calss the EntitiesController#save_entity
  def apply_edit
    entity_saved=false
    # Try to save the entity
    begin
      entity_saved, @invalid_list= Entity.save_entity(params)
      
    rescue RuntimeError => e
      if e.message == "no detail saved"
        render :text => "__ERROR__"+t("madb_no_detail_saved_enter_at_least_one_valid_value")
        return
        #we should raise other exceptions
      end

    end


    if entity_saved #sets @instance
      @instance = entity_saved
      
      # if saved and we have auser of this database, list entites otherwise nothing
      if session["user"] and user_dbs.include? @db
#returning json here caused the file dialog to open...
#might have to be adapted in the gallery-form code


        #FIXME PROBLEM HERE, we don't return the correct JSON

        yui_hash = JSON.parse(@instance.to_hash.to_json).inject({}){ |a,v| k="['"+v[0]+"']" ;  a.merge({k => v[1]}) }
        render :text => yui_hash.to_json and return
        #render :text => @instance.to_hash.to_json and return
      else
        # this case happens with public forms
        render :nothing => true and return;
      end
                       
    else
      # Otherwise if not saved, we simply list the fields that are 
      # invalid.
      headers['Content-Type']='text/html; charset=UTF-8'
      render :text => @invalid_list.join('######')
      return

    end
  end

  # *Description*
  #   Unlinks two instances.
  #   
  # *REST_API*
  #   DELETE /entities/:entity_id/instances/:id 
  #   DELETE databases/:database_id/entities/:entity_id/instances/:id 
  #   
  #  REST API params:
  #   parent_id is the parnet participent of the relation
  #   child_id is the child participant of the relation
  #   and either of these should be provided.
  #   relation_id is the id of the type of the relation with which the two
  #   instances are linked.
      
  def unlink
    
    if params["parent_id"]
      parent_id = "parent_id"
      child_id = "id"
      render_id = "parent_id"
      type = "children"
    else
      parent_id="id"
      child_id = "child_id"
      render_id = "child_id"
      type = "parents"
    end
  	Link.delete_all( [ "parent_id=? AND child_id=? AND relation_id=?", params[parent_id],params[child_id],params["relation_id"] ] )
    #overwrite_params doesn't work with render_component
      render :json => { :status => :success}
  end

  # *Description*
  # This function lists all the available entities which can be linked to 
  # the given entity.
  def list_available_for_link
    setup_sort_and_dir
    @relation = Relation.find params["relation_id"]
    if params["parent_id"]
      related_id = "child_id"
      self_id = "parent_id"
      @entity = @relation.child
      #if parent_side_type is one, we filter out all entities already link at the one side
      #if parent_side_type is many, we filter out all entities already link to this entity
      if @relation.parent_side_type.name!="one"
        @link_to_many = 't'
      end
      other_side_type_filter= " and #{CrosstabObject.connection.quote_string(self_id)}=#{CrosstabObject.connection.quote_string(params[self_id].to_s)}"
    else
      related_id = "parent_id"
      self_id = "child_id"
      @entity = @relation.parent
      #if child_side_type is one, we filter out all entities already linked at the one side
      #if child_side_type is many, we filter out only entities already linked to this entity
      if @relation.child_side_type.name!="one"
        @link_to_many = 't'
      end
      other_side_type_filter= " and #{self_id}=#{CrosstabObject.connection.quote_string(params[self_id].to_s)}"
    end

    @details = @entity.details_hash
    filter_clause = crosstab_filter
    if @link_to_many!='t'
      link_filter = "id not in (select #{related_id} from links where relation_id = #{@relation.id})"
    else
      link_filter = "id not in (select #{related_id} from links where relation_id = #{@relation.id} #{other_side_type_filter})"
    end

    existing_links = Link.count_by_sql("select count(*) from links where relation_id = #{@relation.id} #{other_side_type_filter}")
    if @link_to_many!='t' and existing_links>0 
      @list = []
      @paginator = nil 
    else
      crosstab_result = @entity.crosstab_query(:display => "detail")
      crosstab_query     = crosstab_result[:query]
      #@ordered_fields is used in the csv view
      @ordered_fields   = crosstab_result[:ordered_fields]
      @list, @paginator = @entity.get_paginated_list(:filters => [ filter_clause , link_filter ], :highlight => params[:highlight], :default_page => params[list_id+"_page"]|| ((params[:startIndex].to_i/list_length).ceil + 1), :order_by => @sort , :direction => @dir, :list_length => list_length )
    end

    respond_to do |format|
      format.js { render :action => 'entities_list' }
      format.csv { render :action => 'entities_list' }
    end
  end




  def link_to_existing
    @relation = Relation.find params["relation_id"]
    if params["parent_id"]
      @yui_list_id = "e_#{@relation.id}_from_parent_to_child_linkable_list"
      @related_id = "child_id"
      @self_id = "parent_id"
      @entity = @relation.child
    else
      @yui_list_id = "e_#{@relation.id}_from_child_to_parent_linkable_list"
      @related_id = "parent_id"
      @self_id = "child_id"
      @entity = @relation.parent
    end
		#FIXME: check this is ok if we have a relation to the same entity. It will then appear in children and parents related entities.
  end

  def link_to_new
    init_add_form
    @relation = Relation.find params['relation_id']
    if params["parent_id"] 
      linked_id = "parent_"+params["parent_id"]
      @yui_form_id = "e_#{@relation.id}_from_parent_to_child_form"
    elsif params["child_id"] 
      linked_id = "child_"+params["child_id"]
      @yui_form_id = "e_#{@relation.id}_from_child_to_parent_form"
    end
    @form_id = @relation.id.to_s+"_"+@entity.id.to_s+"_"+linked_id
  end

  def apply_link_to_new
    entity_saved=false
    begin
      entity_saved, @invalid_list = Entity.save_entity(params)
      @instance = entity_saved
    rescue RuntimeError => e
      if e.message == "no detail saved"
        render :text => "__ERROR__"+t("madb_no_detail_saved_enter_at_least_one_valid_value")
        return
      end
    end
    if entity_saved
      # fetch instance to to be linked
      if params["parent_id"]
              child = @instance
              parent = Instance.find params["parent_id"]
      elsif params["child_id"]
          parent = @instance
          child = Instance.find params["child_id"]
      else
          raise "Missing parameter parent_id (#{params["parent_id"]}) or child_id (#{params["child_id"]})"
      end
      relation = Relation.find params["relation_id"]
      # link instances
      result = link_instances(parent,relation,child)
      if result[:status]==:success
        yui_hash = JSON.parse(@instance.to_hash.to_json).inject({}){ |a,v| k="['"+v[0]+"']" ;  a.merge({k => v[1]}) }
        info= { :status => :success, :record => yui_hash} 
        render :text => info.to_json  and return
      else
        @instance.destroy
        render :json => result, :status => 400 and return
      end
    else
      headers['Content-Type']='text/plain; charset=UTF-8'
      render :text => @invalid_list.join('######')
      return
    end
  end

  def link_instances(parent,relation,child)
	begin
          if relation.parent_side_type.name=="one"
            #parent side is one, so if child is already linked to one, cannot be linked again.....
            if Link.count(:conditions => "child_id=#{child.id} and relation_id=#{relation.id}")>0
              raise "madb_not_respecting_to_one_relation"
            end
          end
          if relation.child_side_type.name=="one"
            if Link.count(:conditions => "parent_id=#{parent.id} and relation_id=#{relation.id}")>0
              raise "madb_not_respecting_to_one_relation"
            end
          end

          link = Link.new
          link.child = child
          link.parent = parent
          link.relation = relation
          link.save
          return { :status => :success }

	rescue ActiveRecord::StatementInvalid=> @e
          # sql statement failedn check if record is already linked
          existing_links = Link.find(:all, :conditions => [ "relation_id=? AND parent_id=? AND child_id=?", params["relation_id"],params["parent_id"],params["id"]])
          if existing_links.length>0
            msg  = t("madb_error_record_already_linked")
          else
            msg = t "madb_an_error_occured"
          end
          return { :status => :error, :message => msg }
	rescue RuntimeError => @e
          if @e.message=="madb_not_respecting_to_one_relation"
            msg = t("madb_not_respecting_to_one_relation")
          end
          return { :status => :error, :message => msg }
	rescue Exception => @e
          msg = t("madb_an_error_occured")
          return { :status => :error, :message => msg }
        ensure
	end
  end

  # *Description*
  # Links two existing instances
  # 
  # *REST_API*
  #   id of the instance is to be provided in params[:id] and
  #   params[:parent_id] | params[:child_id] along with the relation_id
  #
  def link
    if params["child_id"]
      child_id = "child_id"
      parent_id = "id"
    else
      parent_id = "parent_id"
      child_id = "id"
    end

    relation = Relation.find params["relation_id"]
    parent = Instance.find params[parent_id]
    child = Instance.find params[child_id]

    result = link_instances(parent,relation,child)
    if result[:status]==:success
      render :json => result  and return
    else
      render :json => result, :status => 400 and return
    end
  end


  # *Description*
  #   Lists the related entities.
  #
  # REST Parameters:
  #   reltaion_id
  #   type
  #
  def related_entities_list
    # sets @sort and @dir
    setup_sort_and_dir

    @relation = Relation.find params["relation_id"]
    @type = params["type"]
    @details = {}
    #this is changed later in the code if necessary
    @link_to_many = 'f'

    # if the type is childeren, we are connecting parent to childeren
    # otherwise the other way around.
    if @type == "children"
      type = {:from => "parent", :to => "child"}
    else
      type = {:from => "child", :to => "parent"}
    end

    @link_type = type[:to]
    @relation_name = @relation.send("from_#{type[:from]}_to_#{type[:to]}_name")
    @source_id = "#{type[:from]}_id"
    linked_entity_object = @relation.send(type[:to])
    @instance = Instance.find params["id"]
#    if @relation.send("#{type[:to]}_side_type").name!="one"
#      @link_to_many = 't'
#    end

    @details = linked_entity_object.details_hash

    order = order_by

    clause = crosstab_filter

    # THIS GENERATES LOTS OF QUERIES LIKE  SELECT * FROM instances WHERE instances.id = 139 LIMIT 1
    if @type=="children"
      ids_to_keep = @instance.links_to_children.reject{ |l| l.relation!=@relation }.collect { |l| l.send("#{@link_type}_id")  }.uniq.join(",")
    elsif @type=="parents"
      ids_to_keep = @instance.links_to_parents.reject{ |l| l.relation!=@relation }.collect { |l| l.send("#{@link_type}_id")  }.uniq.join(",")
    end


    filters =  ["id in (#{ids_to_keep})",  clause]
    crosstab_result = linked_entity_object.crosstab_query()
    if crosstab_result
      crosstab_query     = crosstab_result[:query]
      @not_in_list_view  = crosstab_result[:not_in_list_view]
      # ordered_fields is used by the csv view
      @ordered_fields   = crosstab_result[:ordered_fields]
    else
      crosstab_count = 0
      linked_count=0
    end

    if ids_to_keep.length>0
      count_row =  CrosstabObject.connection.execute("select count(*) from #{crosstab_query} #{join_filters(filters)}")[0]
      crosstab_count = count_row[0] ? count_row[0] : count_row['count']
      #use linked_count result to determine links display (to associate other entries)
      linked_row =  CrosstabObject.connection.execute("select count(*) from #{crosstab_query}  where id in (#{ids_to_keep}) ")[0]
      linked_count = linked_row[0] ? linked_row[0] : linked_row['count']
    else
      crosstab_count =0
    end
    if crosstab_count.to_i > 0
      #page_number = page_number(crosstab_query)
      if params["highlight"]
        response.headers["MYOWNDB_highlight"]  =  params["highlight"].to_s
      end

      @list, @paginator = linked_entity_object.get_paginated_list(:filters =>  filters , :format => params[:format],   :default_page => ((params[:startIndex].to_i/list_length).ceil + 1), :order_by => @sort , :direction => @dir, :list_length => list_length)
    else
      @list = []
    end

    #to many relation
#    if @link_to_many=='t'
#      #check if instances available for linking
#        link_to_many = @relation.send("#{type[:to]}_side_type").name=='many'
#        link_from_many = @relation.send("#{type[:from]}_side_type").name=='many'
#        if link_from_many
#          available_instances = Instance.find(:all, :conditions => "entity_id=#{@relation.send(type[:to]).id} and id not in (select #{type[:to]}_id from links where relation_id = #{@relation.id} and #{type[:from]}_id=#{@instance.id})")
#        else
#          available_instances = Instance.find(:all, :conditions => "entity_id=#{@relation.send(type[:to]).id} and id not in (select #{type[:to]}_id from links where relation_id = #{@relation.id})")
#        end
#    end
    params[:format]='html' if params[:format].nil?
    respond_to do |format|
      format.html {  }
      format.js { render :action => 'entities_list' }
      format.csv { render :action => 'entities_list' }
    end


  end



  # *Description*
  #   The output from the actions of this contorller can be presented in variuos
  #   forms. It might be embded like through an AJAX request, or it might be
  #   presented in a separate popup window, or it can be in the main application
  #   window. This function determines the layout or presentation of the content
  #   based on the requested actions and type of request.
  #
  def determine_layout
      #no layout if
      # -action=related_entities_list and not popup
      # -action=list_availaible_for_link or entities_list
      # -xhr request
      # -embedded!=nil
      # -displayed as component (=> embedded == true)
		# removed or (["list_available_for_link", "entities_list"].include? params["action"])
    if ( %w(entities_list list_available_for_link related_entities_list public_form_javascript).include? params["action"] and params["popup"].nil?)  or (request.xml_http_request?) or (! params["embedded"].nil?) or (embedded?)
      return nil
      # Otherwise, if the params[:popup] is true and the request is not an
      # AJAX requst then the layout is popup otherwise application.
    elsif params["popup"]=='t' and (!request.xml_http_request?)
      return "popup"
    else
      return "application"
    end
  end

  def delete
    entity=Instance.find( params["id"] ).entity
    begin
      Instance.destroy(params["id"])
    rescue Exception => e
      flash["error"] = t("madb_error_occured_when_deleting_entity")
      logger.error "ERROR : in entities_controller, line #{__LINE__} :   #{e}"
    end
    respond_to do |format|
      format.html { redirect_to :overwrite_params => { :action => "entities_list", :id => entity.id , :highlight => nil } }
      format.js { render :json => { :status => :success } }
    end
  end


  # *Description*
  #  Deletes an instance
  # DELETE entities/:entity_id/instances/:id
  # DELETE /databases/:database_id/instances/:id
  
  def destroy()
      begin
        Instance.destroy(params[:id])
      rescue Exception => e
        flash["error"] = t("madb_error_occured_when_deleting_entity")
        logger.error "ERROR : in entities_controller, line #{__LINE__} :   #{e}"
        return e
      end
      return nil
  end
  
  def check_detail_value_validity
    #called by javascript form observer
    detail = Detail.find params["detail_id"]
    value = params["detail_value"]
    detail_value_class = class_from_name(detail.data_type.class_name)
    headers["Access-Control-Allow-Origin"]="*"
    if detail_value_class.valid?(value, :session => session)
      render :text => '1'
    else
      render :text => '0'
    end
  end


  def public_form
      @entity = Entity.find params["id"]
      @verification_string = String.random
      @verification_hash = Digest::SHA1.digest(@verification_string)
      session["public_form_check"] =@verification_string
      if params['embedded']=='t' or params[:format]=='js'
        render :layout => false
      else
        render :layout => "public"
      end
  end

  private
  def entity_id
    # if the intended action is public_form or public_form_javascript then
    # the params[:id] is an entitiy id.
    if params["action"]=="public_form" or params["action"]=="public_form_javascript"
      entity_id = params["id"]
    end
    
    # if the intended action is apply_edit then the params[:entity] contains the
    # entity id.
    # reject request if instance_id is not -1, ie if it is for an update 
    if params["action"]=="apply_edit"
      entity_id = params["entity"]
    end
    return entity_id
  end

# returns a quoted version of the requestion sort direction
  def sort_direction
    CrosstabObject.connection.quote_string(@dir.to_s)
  end

# returns a quoted version of the requestion column sorting
  def order_by
      order=@sort
  end
  def crosstab_filter
    if detail_filter.nil?
      return ""
    else
      detail = Detail.find detail_filter
      return "#{CrosstabObject.connection.quote_column_name(detail.name)}::text ilike '#{leading_wildcard}#{CrosstabObject.connection.quote_string(params["value_filter"].to_s)}#{trailing_wildcard}'"
    end
  end
    

  def setup_sort_and_dir
    @sort = params[:sort].nil? ? "id" : params[:sort]
    @dir =  params[:dir].nil? ? "ASC" : params[:dir]
  end
  def list_length
     params[:results].nil? ? MadbSettings.list_length : params[:results].to_i
  end
  def handle_options_request
    if request.env["REQUEST_METHOD"]=="OPTIONS"
      headers["Access-Control-Allow-Origin"]="*"
      headers["Access-Control-Allow-Methods"] = "*"
      headers["Access-Control-Allow-Headers"] = "x-requested-with"
      render :nothing => true
      return
    end
  end

end
