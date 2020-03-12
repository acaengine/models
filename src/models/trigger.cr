require "json"
require "rethinkdb-orm"
require "time"

require "./base/model"

module PlaceOS::Model
  class Trigger < ModelBase
    include RethinkORM::Timestamps
    table :trigger

    attribute name : String, es_type: "keyword"
    attribute description : String

    # Full path allows resolution in macros
    attribute actions : PlaceOS::Model::Trigger::Actions = ->{ Actions.new }, es_type: "object"
    attribute conditions : PlaceOS::Model::Trigger::Conditions = ->{ Conditions.new }, es_type: "object"

    # In milliseconds
    attribute debounce_period : Int32 = 0
    attribute important : Bool = false

    METHODS = %w(GET POST PUT PATCH DELETE)
    attribute enable_webhook : Bool = false
    attribute supported_methods : Array(String) = ["POST"]

    def supported_method?(method)
      !!(supported_methods.try &.includes?(method))
    end

    has_many(
      child_class: TriggerInstance,
      dependent: :destroy,
      foreign_key: "trigger_id",
      collection_name: :trigger_instances
    )

    # Allows filtering in cases of a Trigger belonging to a single ControlSystem
    belongs_to ControlSystem, foreign_key: "control_system_id"

    # ---------------------------
    # VALIDATIONS
    # ---------------------------

    validate ->(this : Trigger) {
      return unless (supported_methods = this.supported_methods)
      invalid = supported_methods - METHODS
      this.validation_error(:supported_methods, "contains invalid methods: #{invalid.join(", ")}") unless invalid.empty?
    }

    validates :name, presence: true

    validate ->(this : Trigger) {
      if (actions = this.actions) && !actions.valid?
        actions.errors.each do |e|
          this.validation_error(:action, e.to_s)
        end
      end

      if (conditions = this.conditions) && !conditions.valid?
        conditions.errors.each do |e|
          this.validation_error(:condition, e.to_s)
        end
      end
    }

    # Conditions
    ###########################################################################

    class Conditions < SubModel
      attribute comparisons : Array(Comparison) = ->{ [] of Comparison }
      attribute time_dependents : Array(TimeDependent) = ->{ [] of TimeDependent }

      validate ->(this : Conditions) {
        if (time_dependents = this.time_dependents)
          this.collect_errors(:time_dependents, time_dependents)
        end

        if (comparisons = this.comparisons)
          this.collect_errors(:comparisons, comparisons)
        end
      }

      class TimeDependent < SubModel
        enum Type
          At
          Cron
        end

        enum_attribute type : Type, column_type: String

        attribute time : Time, converter: Time::EpochConverter
        attribute cron : String

        validates :type, presence: true
      end

      class Comparison < SubModel
        attribute left : Value
        attribute operator : String
        attribute right : Value

        alias Value = StatusVariable | Constant

        # Constant value
        alias Constant = Int64 | Float64 | String | Bool

        # Status of a Module
        alias StatusVariable = NamedTuple(
          # Module that defines the status variable
          mod: String,
          # Unparsed hash of a status variable
          status: String,
          # Keys to look up in the module
          keys: Array(String),
        )

        OPERATORS = {
          "equal", "not_equal", "greater_than", "greater_than_or_equal",
          "less_than", "less_than_or_equal", "and", "or", "exclusive_or",
        }

        validates :operator, inclusion: {in: OPERATORS}, presence: true
      end
    end

    # Actions
    ###########################################################################

    class Actions < SubModel
      attribute functions : Array(Function) = ->{ [] of Function }
      attribute mailers : Array(Email) = ->{ [] of Email }

      validate ->(this : Actions) {
        if (mailers = this.mailers)
          this.collect_errors(:mailers, mailers)
        end
        if (functions = this.functions)
          this.collect_errors(:functions, functions)
        end
      }

      class Email < SubModel
        attribute emails : Array(String)
        attribute content : String = ->{ "" }

        validates :emails, presence: true
      end

      class Function < SubModel
        attribute mod : String
        attribute method : String
        attribute args : Hash(String, JSON::Any) = ->{ {} of String => JSON::Any }

        validates :mod, presence: true
        validates :method, presence: true
      end
    end
  end
end