require "uri"

require "../engine-models"

module Engine::Model
  class Module < ModelBase
    table :mod

    # The classes / files that this module requires to execute
    # Defines module type

    # Requires driver_id to be set
    belongs_to Driver
    belongs_to ControlSystem

    attribute ip : String
    attribute tls : Bool
    attribute udp : Bool
    attribute port : Int32
    attribute makebreak : Bool = false

    # HTTP Service module
    attribute uri : String

    # Custom module names (in addition to what is defined in the driver)
    attribute custom_name : String
    attribute settings : String = "{}"

    attribute updated_at : Time = ->{ Time.utc_now }, converter: Time::EpochConverter
    attribute created_at : Time = ->{ Time.utc_now }, converter: Time::EpochConverter

    enum_attribute role : Driver::Role # cache the driver role locally for load order

    # Connected state in model so we can filter and search on it
    attribute connected : Bool = true
    attribute running : Bool = false
    attribute notes : String

    # Don't include this module in statistics or disconnected searches
    # Might be a device that commonly goes offline (like a PC or Display that only supports Wake on Lan)
    attribute ignore_connected : Bool = false
    attribute ignore_startstop : Bool = false

    # Finds the systems for which this module is in use
    def systems
      ControlSystem.by_module_id(self.id)
    end

    # Getter for the module's host
    def hostname
      case role
      when Driver::Role::SSH, Driver::Role::Device
        self.ip
      when Driver::Role::Service
        uri = self.uri || self.driver.try &.default_uri
        uri.try { |u| URI.parse(u).host }
      else
        # No hostname for Logic module
        nil
      end
    end

    # Setter for Device module ip
    def hostname=(host : String)
      @ip = host
    end

    # Set driver and role
    def driver=(driver : Driver)
      previous_def(driver)
      self.role = driver.role
    end

    validates :driver, presence: true

    validate ->(this : Module) {
      driver = this.driver
      return if driver.nil?
      case driver.role
      when Driver::Role::Service
        this.validate_service_module
      when Driver::Role::Logic
        this.validate_logic_module
      when Driver::Role::Device, Driver::Role::SSH
        this.validate_device_module
      end
    }

    protected def validate_service_module
      self.role = Driver::Role::Service
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
  end
end
