require "rethinkdb-orm"

require "../settings"

module PlaceOS::Model
  module SettingsHelper
    # Attain the settings associated with the model
    #
    def settings_collection
      RethinkORM::AssociationCollection(self.class, Settings).new(self)
    end

    # Get the settings at a particular encryption level
    #
    def settings_at(encryption_level : Encryption::Level)
      raise IndexError.new unless (settings = settings_at?(encryption_level))
      settings
    end

    # Get the settings at a particular encryption level
    #
    def settings_at?(encryption_level : Encryption::Level)
      Settings.master_settings_query(self.id.as(String)) do |q|
        q.filter({encryption_level: encryption_level.to_i})
      end.first?
    end

    # Decrypts and merges all settings for the model
    #
    def all_settings : Hash(YAML::Any, YAML::Any)
      master_settings.reduce({} of YAML::Any => YAML::Any) do |acc, settings|
        # Parse and merge into accumulated settings hash
        acc.merge!(settings.any)
      end
    end

    # Decrypted JSON object for configuring drivers
    #
    def settings_json : String
      all_settings.to_json
    end

    # Query the master settings attached to a model
    #
    def master_settings : Array(Settings)
      Settings.master_settings_query(self.id.as(String)) { |q| q }
    end
  end
end
