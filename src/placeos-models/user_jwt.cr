require "./base/jwt"

module PlaceOS::Model
  struct UserJWT < JWTBase
    getter iss : String

    @[JSON::Field(converter: Time::EpochConverter)]
    getter iat : Time

    @[JSON::Field(converter: Time::EpochConverter)]
    getter exp : Time

    # getter jti : String

    # Maps to authority domain
    getter aud : String

    # Maps to user id
    getter sub : String

    # OAuth2 Scopes
    getter scope : Array(String)

    @[JSON::Field(key: "u")]
    getter user : Metadata

    enum Permissions
      User         = 0
      Support      = 1
      Admin        = 2
      AdminSupport = 3
    end

    struct Metadata
      include JSON::Serializable
      @[JSON::Field(key: "n")]
      getter name : String
      @[JSON::Field(key: "e")]
      getter email : String
      @[JSON::Field(key: "p")]
      getter permissions : Permissions
      @[JSON::Field(key: "r")]
      getter roles : Array(String)

      def initialize(@name, @email, @permissions = Permissions::User, @roles = [] of String)
      end
    end

    def initialize(@iss, @iat, @exp, @aud, @sub, @user)
    end

    def domain
      @aud
    end

    def id
      @sub
    end

    def is_admin?
      case @user.permissions
      in .admin?, .admin_support?
        true
      in .user?, .support?
        false
      end
    end

    def is_support?
      case @user.permissions
      in .support?, .admin?, .admin_support?
        true
      in .user?
        false
      end
    end
  end
end
