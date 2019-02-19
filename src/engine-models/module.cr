require "rethinkdb-orm"
require "uri"

class Engine::Module < RethinkORM::Base
  table_name :mod

  # The classes / files that this module requires to execute
  # Defines module type
  # Requires dependency_id to be set

  belongs_to Dependency
  belongs_to ControlSystem

  # Device module
  def hostname
    @ip
  end

  def hostname=(host)
    @ip = host
  end

  attribute ip : String
  attribute tls : Boolean
  attribute udp : Boolean
  attribute port : Integer
  attribute makebreak : Boolean, default: false

  # HTTP Service module
  attribute uri : String

  # Custom module names (in addition to what is defined in the dependency)
  attribute custom_name : String
  attribute settings : Hash(String, String), default: {} of String => String

  attribute updated_at : Integer, default: ->{ Time.now }
  attribute created_at : Integer, default: ->{ Time.now }
  attribute role # cache the dependency role locally for load order

  # Connected state in model so we can filter and search on it
  attribute connected : Boolean, default: true
  attribute running : Boolean, default: false
  attribute notes : String

  # Don't include this module in statistics or disconnected searches
  # Might be a device that commonly goes offline (like a PC or Display that only supports Wake on Lan)
  attribute ignore_connected : Boolean, default: false
  attribute ignore_startstop : Boolean, default: false

  # helper method for looking up the manager
  def manager
    Control.instance.loaded? self.id
  end

  # Returns the node currently running this module
  def node
    # NOTE:: Same function in control_system.cr
    @node_id ||= self.edge_id.to_sym
    Control.instance.nodes[@node_id]
  end

  # Loads all the modules for this node in ascending order by default
  #  (device, service then logic)
  # view :all, emit_key: :role

  # # Finds all the modules belonging to a particular dependency
  # index_view :dependency_id, find_method: :dependent_on
  # index_view :edge_id,       find_method: :on_node

  # The systems this module is in use
  def systems
    ControlSystem.using_module(self.id)
  end

  def hostname
    case role
    when 0, 1 # SSH and Device
      self.ip
    when 2 # Service
      URI.parse(self.uri).host
    end
  end

  validates :dependency, presence: true
  validates :edge_id, presence: true
  validate :configuration

  protected def configuration
    return unless dependency
    case dependency.role
    when :ssh
      self.role = 0
      self.port = (self.port || dependency.default || 22).to_i

      errors.add(:ip, "cannot be blank") if self.ip.blank?
      errors.add(:port, "is invalid") unless self.port.between?(1, 65535)

      self.tls = true # display the padlock icon in backoffice
      self.udp = nil

      begin
        url = URI.parse("http://#{self.ip}:#{self.port}/")
        url.scheme && url.host
      rescue
        errors.add(:ip, "address / hostname or port are not valid")
      end
    when :device
      self.role = 1
      self.port = (self.port || dependency.default).to_i

      errors.add(:ip, "cannot be blank") if self.ip.blank?
      errors.add(:port, "is invalid") unless self.port.between?(1, 65535)

      # Ensure tls and upd values are correct
      # can't have udp + tls
      self.udp = !!self.udp
      if self.udp
        self.tls = false
      else
        self.tls = !!self.tls
      end

      begin
        url = URI.parse("http://#{self.ip}:#{self.port}/")
        url.scheme && url.host
      rescue
        errors.add(:ip, "address / hostname or port are not valid")
      end
    when :service
      self.role = 2
      self.udp = nil

      begin
        self.uri ||= dependency.default
        url = URI.parse(self.uri)
        url.host                         # ensure this can be parsed
        self.tls = url.scheme == "https" # secure indication
      rescue
        errors.add(:uri, "is an invalid URI")
      end
    else                    # logic
      self.connected = true # it is connectionless
      self.tls = nil
      self.udp = nil
      self.role = 3
      if control_system.nil?
        errors.add(:control_system, "must be associated")
      end
    end
  end

  before_destroy :unload_module

  protected def unload_module
    Control.instance.unload(self.id)

    # Find all the systems with this module ID and remove it
    self.systems.each do |cs|
      cs.modules.delete(self.id)
      cs.version += 1
      cs.save!
    end
  end
end
