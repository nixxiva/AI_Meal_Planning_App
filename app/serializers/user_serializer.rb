class UserSerializer
  include JSONAPI::Serializer
  attributes :id, :first_name, :last_name, :email, :role
end
