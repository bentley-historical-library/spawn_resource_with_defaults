Rails.application.config.after_initialize do

  ResourcesController.class_eval do

    def new
      @resource = Resource.new(:title => I18n.t("resource.title_default", :default => ""))._always_valid!

      if params[:accession_id]
        acc = Accession.find(params[:accession_id], find_opts)

        if acc
          # Modify this to send along the user_prefs['default_values'] to the modified populate_from_accession
          @resource.populate_from_accession(acc, user_prefs['default_values'])
          flash.now[:info] = I18n.t("resource._frontend.messages.spawned", JSONModelI18nWrapper.new(:accession => acc))
          flash[:spawned_from_accession] = acc.id
        end

      elsif user_prefs['default_values']
        defaults = DefaultValues.get 'resource'

        if defaults
          @resource.update(defaults.values)
          @form_title = "#{I18n.t('actions.new_prefix')} #{I18n.t('resource._singular')}"
        end

      end

      return render_aspace_partial :partial => "resources/new_inline" if params[:inline]
    end
  end

  Resource.class_eval do
    # Modify this function definition to add a user_prefs_default_values parameter
    def populate_from_accession(accession, user_prefs_default_values=False)
      values = accession.to_hash(:raw)

      # Recursively remove bits that don't make sense to copy (like "lock_version"
      # properties)
      values = JSONSchemaUtils.map_hash_with_schema(values, JSONModel(:accession).schema,
                                                          [proc { |hash, schema|
                                                            hash = hash.clone
                                                            hash.delete_if {|k, v| k.to_s =~ /^(id_[0-9]|lock_version|instances|deaccessions|collection_management|user_defined|external_documents)$/}
                                                            hash
                                                          }])

      # We'll replace this with our own relationship, linking us back to the
      # accession we were spawned from.
      values.delete('related_accessions')

      notes ||= []

      if accession.content_description
        notes << JSONModel(:note_multipart).from_hash(:type => "scopecontent",
                                                      :label => I18n.t('accession.content_description'),
                                                      :subnotes => [{
                                                                      'content' => accession.content_description,
                                                                      'jsonmodel_type' => 'note_text'
                                                                    }])
      end

      # Don't make a physdesc not from this
      #if accession.condition_description
        #notes << JSONModel(:note_singlepart).from_hash(:type => "physdesc",
        #                                               :label => I18n.t('accession.condition_description'),
        #                                               :content => [accession.condition_description])
      #end

      self.related_accessions = [{'ref' => accession.uri, '_resolved' => accession}]

      # Comment this out, we'll be adding notes a little later
      #self.notes = notes

      self.update(values)

      self.rights_statements = Array(accession.rights_statements).map {|rights_statement|
        rights_statement.clone.tap {|r| r.delete('identifier')}
      }

      # Comment these out and run this check at the very end
      #if !self.extents || self.extents.empty?
        #self.extents = [JSONModel(:extent).new._always_valid!]
      #end

      #if !self.dates || self.dates.empty?
        #self.dates = [JSONModel(:date).new._always_valid!]
      #end

      # Begin plugin customizations

      if accession.access_restrictions_note
          notes << JSONModel(:note_multipart).from_hash(:type => "accessrestrict",
                                                        :label => "",
                                                        :subnotes => [{
                                                                        'content' => accession.access_restrictions_note,
                                                                        'jsonmodel_type' => 'note_text'
                                                                      }])
      end

      if accession.use_restrictions_note
          notes << JSONModel(:note_multipart).from_hash(:type => "userestrict",
                                                        :label => "",
                                                        :subnotes => [{
                                                                        'content' => accession.use_restrictions_note,
                                                                        'jsonmodel_type' => 'note_text'
                                                                      }])
      end

      # For some reason, extents were either not getting added or were being overwritten later on
      if accession.extents && !accession.extents.empty? && !self.extents && !self.extents.empty?
          self.extents = accession.extents
      end

      if user_prefs_default_values
          defaults = DefaultValues.get 'resource'

          if defaults
              default_values = defaults.values
              note_types = notes.map {|note| note[:type]}
              default_notes = default_values["notes"]

              notes.concat(default_notes.reject {|note| note_types.include?(note["type"])})
              default_values.delete("notes")
              # Don't overwrrite the existing extents if they exist
              if self.extents && !self.extents.empty?
                  default_values.delete("extents")
              end
              self.update(default_values)
          end
      end

      self.notes = notes

      if !self.extents || self.extents.empty?
        self.extents = [JSONModel(:extent).new._always_valid!]
      end

      if !self.dates || self.dates.empty?
        self.dates = [JSONModel(:date).new._always_valid!]
      end

    end

  end

end
