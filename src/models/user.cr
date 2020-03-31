require "CrystalEmail"
require "digest/md5"
require "rethinkdb-orm"
require "crypto/bcrypt/password"
require "./authority"
require "./base/model"

module PlaceOS::Model
  class User < ModelBase
    include RethinkORM::Timestamps
    table :user

    belongs_to Authority

    attribute name : String, es_type: "keyword"
    attribute nickname : String
    attribute email : String
    attribute phone : String
    attribute country : String
    attribute image : String
    attribute ui_theme : String
    attribute metadata : String

    attribute login_name : String
    attribute staff_id : String
    attribute first_name : String
    attribute last_name : String
    attribute building : String

    attribute password_digest : String, mass_assignment: false
    attribute email_digest : String, mass_assignment: false
    attribute card_number : String

    attribute deleted : Bool = false

    validates :email, presence: true
    validates :authority_id, presence: true

    # Validate email format
    validate ->(this : User) {
      return unless (email = this.email)
      this.validation_error(:email, "is an invalid email") unless email.is_email?
    }

    before_save :create_email_digest

    # Sets email_digest to allow user look up without leaking emails
    #
    protected def create_email_digest
      self.email_digest = Digest::MD5.hexdigest(self.email.as(String))
    end

    def self.find_by_email(authority_id : String, email : String)
      User.where(email: email, authority_id: authority_id).first?
    end

    # Ensure email is unique, prepends authority id for searching
    #
    ensure_unique :email, scope: [:authority_id, :email] do |authority_id, email|
      {authority_id, email.strip.downcase}
    end

    ensure_unique :login_name, scope: [:authority_id, :login_name] do |authority_id, login_name|
      {authority_id, login_name.strip.downcase}
    end

    ensure_unique :staff_id, scope: [:authority_id, :staff_id] do |authority_id, staff_id|
      {authority_id, staff_id.strip.downcase}
    end

    # Publically visible fields
    PUBLIC_DATA = {
      :id, :email_digest, :nickname, :name, :first_name, :last_name,
      :country, :building, {field: :created_at, serialise: :to_unix},
    }

    # Admin visible fields
    ADMIN_DATA = {
      # Public Visible
      :id, :email_digest, :nickname, :name, :first_name, :last_name,
      :country, :building, {field: :created_at, serialise: :to_unix},
      # Admin Visible
      :sys_admin, :support, :email, :phone,
    }

    subset_json(:as_public_json, PUBLIC_DATA)
    subset_json(:as_admin_json, ADMIN_DATA)

    def self.find_by_login_name(login_name : String)
      User.get_all([login_name], index: :login_name).first?
    end

    def self.find_by_staff_id(staff_id : String)
      User.get_all([staff_id], index: :staff_id).first?
    end

    attribute sys_admin : Bool = false

    attribute support : Bool = false

    def is_admin?
      !!(@sys_admin)
    end

    def is_support?
      !!(@support)
    end

    before_save :build_name

    def build_name
      if self.first_name
        self.name = "#{self.first_name} #{self.last_name}"
      end
    end

    # ----------------
    # Indices
    # ----------------

    secondary_index :authority_id

    def by_authority_id(auth_id : String)
      User.get_all([auth_id], index: :authority_id)
    end

    secondary_index :sys_admin

    def self.find_sys_admins
      User.get_all([true], index: :sys_admin)
    end

    # PASSWORD ENCRYPTION::
    # ---------------------
    alias Password = Crypto::Bcrypt::Password
    @password : Password? = nil

    def password : Password
      @password ||= Password.new(self.password_digest.not_nil!)
    end

    def password=(new_password : String) : String
      @password = Password.create(new_password)
      self.password_digest = @password.to_s
      new_password
    end
  end
end
