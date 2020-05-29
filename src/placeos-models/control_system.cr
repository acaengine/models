require "rethinkdb-orm"
require "time"
require "uri"

require "./base/model"
require "./settings"
require "./utilities/settings_helper"

module PlaceOS::Model
  class ControlSystem < ModelBase
    include RethinkORM::Timestamps
    include SettingsHelper

    table :sys

    before_save :update_features

    attribute name : String, es_type: "keyword"
    attribute description : String

    # Room search meta-data
    # Building + Level are both filtered using zones
    attribute email : String
    attribute features : String
    attribute bookable : Bool = false
    attribute display_name : String
    attribute code : String
    attribute type : String
    attribute capacity : Int32 = 0
    attribute map_id : String

    # Provide a email lookup helpers
    secondary_index :email

    # The number of UI devices that are always available in the room
    # i.e. the number of iPads mounted on the wall
    attribute installed_ui_devices : Int32 = 0

    # IDs of associated models
    attribute zones : Array(String) = [] of String, es_type: "keyword"
    attribute modules : Array(String) = [] of String, es_type: "keyword"

    # Encrypted yaml settings, with metadata
    has_many(
      child_class: Settings,
      collection_name: "settings",
      foreign_key: "parent_id",
      dependent: :destroy
    )

    # Single System triggers
    has_many(
      child_class: Trigger,
      dependent: :destroy,
      collection_name: :system_triggers,
      foreign_key: "control_system_id"
    )

    def self.by_zone_id(id)
      ControlSystem.raw_query do |q|
        q.table(ControlSystem.table_name).filter do |doc|
          doc["zones"].contains(id)
        end
      end
    end

    def self.in_zone(id)
      self.by_zone_id(id)
    end

    def self.by_module_id(id)
      ControlSystem.raw_query do |q|
        q.table(ControlSystem.table_name).filter do |doc|
          doc["modules"].contains(id)
        end
      end
    end

    def self.using_module(id)
      self.by_module_id(id)
    end

    # Provide a field for simplifying support
    attribute support_url : String

    attribute version : Int32 = 0

    # Zones and settings are only required for confident coding
    validates :name, presence: true

    # TODO: Ensure unique regardless of casing
    ensure_unique :name do |name|
      "#{name.as(String).strip}"
    end

    # Obtains the control system's modules as json
    # FIXME: Dreadfully needs optimisation, i.e. subset serialisation
    def module_data
      modules = @modules || [] of String
      Module.find_all(modules).to_a.map do |mod|
        # Pick off driver name, and module_name from associated driver
        driver_data = mod.driver.try do |driver|
          {
            :driver => {
              name:        driver.name,
              module_name: driver.module_name,
            },
          }
        end

        if driver_data
          JSON.parse(mod.to_json).as_h.merge(driver_data).to_json
        else
          mod.to_json
        end
      end
    end

    # Obtains the control system's zones as json
    def zone_data
      zones = @zones || [] of String
      Zone.get_all(zones).to_a.map(&.to_json)
    end

    # Triggers
    def triggers
      TriggerInstance.for(self.id)
    end

    # Collect Settings ordered by hierarchy
    #
    # Control System < Zone/n < Zone/(n-1) < ... < Zone/0
    def settings_hierarchy
      # Start with Control System Settings
      settings = master_settings

      # Zone Settings
      zone_ids = zones.as(Array(String))
      zones = Model::Zone.get_all(zone_ids).to_a
      # Merge by highest associated zone
      zone_ids.reverse_each do |zone_id|
        zone = zones.find { |found_zone| found_zone.id == zone_id }
        # TODO: Warn that zone not present rather than error
        # logger.warn "Missing zone: control_system_id=#{id} zone_id=#{zone_id}"
        next unless zone

        settings.concat(zone.master_settings)
      end

      settings.compact
    end

    # Validate support URI
    validate ->(this : ControlSystem) {
      support_url = this.support_url
      if support_url.nil? || support_url.empty?
        this.support_url = nil
      else
        url = URI.parse(support_url)
        url_parsed = !!(url && url.scheme && url.host)
        this.validation_error(:support_url, "is an invalid URI") unless url_parsed
      end
    }

    # Adds modules to the features field,
    # Extends features with extra_features field in settings if present
    protected def update_features
      if (id = @id)
        system = ControlSystem.find(id)
        if system
          mods = system.modules || [] of String
          mods.reject! "__Triggers__"
          @features = mods.join " "
        end
      end

      # TODO:
      # Do a query for the unencrypted settings belonging to the system
      # Append extra features
      #
      # if (settings = @settings)
      #   # Extra features stored in unencrypted settings
      #   settings.find { |(level, _)| level == Encryption::Level::None }.try do |(_, setting_string)|
      #     # Append any extra features
      #     if (extra_features = YAML.parse(setting_string)["extra_features"]?)
      #       @features = "#{@features} #{extra_features}"
      #     end
      #   end
      # end
    end

    # =======================
    # Module Management
    # =======================

    before_destroy :cleanup_modules

    # Remove Modules not associated with any other systems
    # NOTE: Includes compulsory associated Logic Modules
    def cleanup_modules
      modules = self.modules.as(Array(String))
      return if modules.empty?

      # Locate modules that have no other associated ControlSystems
      lonesome_modules = Module.raw_query do |r|
        r.table(Module.table_name).get_all(modules).filter do |mod|
          # Find the control systems that have the module
          r.table(ControlSystem.table_name).filter do |sys|
            sys["modules"].contains(mod["id"])
          end.count.eq(1)
        end
      end

      # Asynchronously remove the modules
      lonesome_modules.map do |m|
        future { m.destroy }
      end.each(&.get)
    end

    # Removes the module from the system and deletes it if not used elsewhere
    #
    def add_module(module_id : String)
      mods = self.modules
      if mods && !mods.includes?(module_id) && ControlSystem.add_module(id.as(String), module_id)
        self.modules = mods | [module_id]
        self.version = ControlSystem.table_query(&.get(id.as(String))["version"]).as_i
      end
    end

    def self.add_module(control_system_id : String, module_id : String)
      response = Model::ControlSystem.table_query do |q|
        q
          .get(control_system_id)
          .update { |sys|
            {
              "modules" => sys["modules"].set_insert(module_id),
              "version" => sys["version"] + 1,
            }
          }
      end

      {"replaced", "updated"}.any? { |k| response[k].try(&.as_i) || 0 > 0 }
    end

    # Removes the module from the system and deletes it if not used elsewhere
    #
    def remove_module(module_id : String)
      mods = self.modules
      if mods && mods.includes?(module_id) && ControlSystem.remove_module(id.as(String), module_id)
        mods.delete(module_id)
        self.version = ControlSystem.table_query(&.get(id.as(String))["version"]).as_i
      end
    end

    def self.remove_module(control_system_id : String, module_id : String)
      response = ControlSystem.table_query do |q|
        q
          .get(control_system_id)
          .update { |sys|
            {
              "modules" => sys["modules"].set_difference([module_id]),
              "version" => sys["version"] + 1,
            }
          }
      end

      return false unless {"replaced", "updated"}.any? { |k| response[k].try(&.as_i) || 0 > 0 }

      # Keep if any other ControlSystem is using the module
      still_in_use = ControlSystem.using_module(module_id).any? do |sys|
        sys.id != control_system_id
      end

      if !still_in_use
        # TODO: Global Logger
        #   logger.info "module (#{module_id}) removed as not in any other systems"
        Module.find(module_id).try(&.destroy)
        # else
        #   logger.info "module (#{module_id}) still in use"
      end

      true
    end

    # =======================
    # Zone Trigger Management
    # =======================

    @remove_zones : Array(String) = [] of String
    @add_zones : Array(String) = [] of String

    @update_triggers = false

    before_save :check_zones

    # Update the zones on the model
    protected def check_zones
      if self.zones_changed?
        previous = self.zones_was || [] of String
        current = self.zones || [] of String

        @remove_zones = previous - current
        @add_zones = current - previous

        @update_triggers = !@remove_zones.empty? || !@add_zones.empty?
      else
        @update_triggers = false
      end
    end

    after_save :update_triggers

    # Updates triggers after save
    #
    # * Destroy Triggers from removed zones
    # * Adds TriggerInstances to added zones
    protected def update_triggers
      return unless @update_triggers

      remove_zones = @remove_zones || [] of String
      unless remove_zones.empty?
        trigs = self.triggers.to_a

        # Remove ControlSystem's triggers associated with the removed zone
        Zone.find_all(remove_zones).each do |zone|
          # Destroy the associated triggers
          triggers = zone.triggers || [] of String
          triggers.each do |trig_id|
            trigs.each do |trig|
              if trig.trigger_id == trig_id && trig.zone_id == zone.id
                trig.destroy
              end
            end
          end
        end
      end

      # Add trigger instances to zones
      add_zones = @add_zones || [] of String
      Zone.find_all(add_zones).each do |zone|
        triggers = zone.triggers || [] of String
        triggers.each do |trig_id|
          inst = TriggerInstance.new(trigger_id: trig_id, zone_id: zone.id)
          inst.control_system = self
          inst.save
        end
      end
    end
  end
end