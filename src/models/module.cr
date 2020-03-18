require "rethinkdb-orm"
require "uri"

require "./base/model"
require "./driver"
require "./settings"
require "./utilities/settings_helper"

module PlaceOS::Model
  class Module < ModelBase
    include RethinkORM::Timestamps
    include SettingsHelper

    table :mod

    # The classes/files that this module requires to execute
    belongs_to Driver, foreign_key: "driver_id"

    belongs_to ControlSystem, foreign_key: "control_system_id"

    attribute ip : String
    attribute port : Int32
    attribute tls : Bool = false
    attribute udp : Bool = false
    attribute makebreak : Bool = false

    # HTTP Service module
    attribute uri : String

    # Module name
    attribute name : String, es_keyword: "keyword", mass_assignment: false

    # Custom module names (in addition to what is defined in the driver)
    attribute custom_name : String

    # Encrypted yaml settings, with metadata
    has_many(
      child_class: Settings,
      collection_name: "settings",
      foreign_key: "parent_id",
      dependent: :destroy
    )

    enum_attribute role : Driver::Role, es_type: "integer" # cache the driver role locally for load order

    # Connected state in model so we can filter and search on it
    attribute connected : Bool = true
    attribute running : Bool = false
    attribute notes : String

    # Don't include this module in statistics or disconnected searches
    # Might be a device that commonly goes offline (like a PC or Display that only supports Wake on Lan)
    attribute ignore_connected : Bool = false
    attribute ignore_startstop : Bool = false

    # Add the Logic module directly to parent ControlSystem
    after_create :add_logic_module

    # Remove the module from associated (if any) ControlSystem
    before_destroy :remove_module

    # ensure the fields are set correctly
    before_save :set_name_and_role

    # Finds the systems for which this module is in use
    def systems
      ControlSystem.by_module_id(self.id)
    end

    # Traverse settings hierarchy, and merge settings
    # [Read more](https://docs.google.com/document/d/1qAbdaYAl5f9rYU6xuT_3TXpnjCqsqeBezhDB-TbHvJA/edit#heading=h.ntoecut6aqkj)
    def merge_settings
      # Accumulate settings, starting with the module's
      settings = [all_settings]

      if role == Driver::Role::Logic
        cs = self.control_system
        raise "Missing control system: module_id=#{@id} control_system_id=#{@control_system_id}" unless cs

        # Control System Settings
        settings.push(cs.all_settings)

        # Zone Settings
        zone_ids = cs.zones.as(Array(String))
        zones = Model::Zone.get_all(zone_ids, index: :id)
        # Merge by highest associated zone
        zone_ids.reverse_each do |zone_id|
          zone = zones.find { |found_zone| found_zone.id == zone_id }
          # TODO: Warn that zone not present rather than error
          raise "Missing zone: module_id=#{@id} zone_id=#{zone_id}" unless zone

          settings.push(zone.all_settings)
        end
      end

      # Driver Settings
      settings.push(driver.as(Model::Driver).all_settings)

      # Merge all settings, serialise to JSON
      settings.compact.reverse.reduce({} of YAML::Any => YAML::Any) do |acc, setting_any|
        acc.merge!(setting_any)
      end.to_json
    end

    # Getter for the module's host
    def hostname
      case role
      when Driver::Role::SSH, Driver::Role::Device
        self.ip
      when Driver::Role::Service, Driver::Role::Websocket
        uri = self.uri || self.driver.try &.default_uri
        uri.try(&->URI.parse(String)).try(&.host)
      else
        # No hostname for Logic module
        nil
      end
    end

    # Setter for Device module ip
    def hostname=(host : String)
      # TODO: resolve hostname?
      @ip = host
    end

    # Set driver and role
    def driver=(driver : Driver)
      previous_def(driver)
      self.role = driver.role
      self.name = driver.module_name
    end

    validates :driver, presence: true

    validate ->(this : Module) {
      driver = this.driver
      return if driver.nil?
      case driver.role
      when Driver::Role::Service, Driver::Role::Websocket
        this.validate_service_module(driver.role)
      when Driver::Role::Logic
        this.validate_logic_module
      when Driver::Role::Device, Driver::Role::SSH
        this.validate_device_module
      end
    }

    protected def validate_service_module(driver_role)
      self.role = driver_role
      self.udp = false

      driver = self.driver
      return if driver.nil?

      self.uri ||= driver.default_uri

      uri = self.uri # URI presence
      unless uri
        self.validation_error(:uri, "not present")
        return
      end

      url = URI.parse(uri)
      url_parsed = !!(url.host && url.scheme)     # Ensure URL can be parsed
      self.tls = !!(url && url.scheme == "https") # Secure indication

      self.validation_error(:uri, "is an invalid URI") unless url_parsed
    end

    protected def validate_logic_module
      self.connected = true # Logic modules are connectionless
      self.tls = nil
      self.udp = nil
      self.role = Driver::Role::Logic
      has_control = !self.control_system_id.nil?

      self.validation_error(:control_system, "must be associated") unless has_control
    end

    protected def validate_device_module
      driver = self.driver
      return if driver.nil?

      self.role = driver.role
      self.port = self.port || driver.default_port || 0

      ip = self.ip
      port = self.port

      # No blank IP
      self.validation_error(:ip, "cannot be blank") if ip && ip.blank?
      # Port in valid range
      self.validation_error(:port, "is invalid") unless port && (1..65_535) === port

      self.tls = false if self.udp

      url = URI.parse("http://#{ip}:#{port}/")
      url_parsed = !!(url.scheme && url.host)

      self.validation_error(:ip, "address / hostname or port are not valid") unless url_parsed
    end

    # Logic modules are automatically added to the ControlSystem
    #
    protected def add_logic_module
      return if role != Driver::Role::Logic
      return unless (cs = self.control_system)

      modules = cs.modules.as(Array(String))
      cs.modules = modules << self.id.as(String)
      cs.version = cs.version.as(Int32) + 1
      cs.save!
    end

    # Remove the module from associated ControlSystem
    #
    protected def remove_module
      mod_id = self.id.as(String)

      ControlSystem.table_query do |q|
        q
          .filter { |sys| sys["modules"].contains(mod_id) }
          .replace { |sys|
            sys.merge({
              "modules" => sys["modules"].set_difference([mod_id]),
              "version" => sys["version"] + 1,
            })
          }
      end
      # TODO: log if there were failures
    end

    protected def set_name_and_role
      driver_ref = driver.not_nil!
      self.role = driver_ref.role
      self.name = driver_ref.module_name
    end
  end
end
