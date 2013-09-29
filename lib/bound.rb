require "bound/version"

class Bound
  def self.new(*args)
    new_bound_class.set_attributes(*args)
  end

  def self.nested(*args)
    new_bound_class.nested(*args)
  end

  def self.optional(*args)
    new_bound_class.optional(*args)
  end

  private

  def self.new_bound_class
    Class.new(BoundClass) do
      initialize_values
    end
  end

  class BoundClass
    class Attribute
      attr_reader :name, :value

      def initialize(name)
        @name = name
      end

      def assign(value)
        @assigned = true
        @value = value
      end

      def assign_nested(bound_definition, value)
        nested_attribute = NestedAttribute.new(bound_definition)
        nested_attribute.assign_to(self, value)
      end

      def call_on(object)
        object.public_send @name
      end

      def valid?
        !required? || is_assigned?
      end

      def required?
        false
      end

      def is_assigned?
        !!@assigned
      end

      def inspect
        "#{@name}=#{@value.inspect}"
      end
    end

    class RequiredAttribute < Attribute
      def required?; true; end
    end

    class NestedAttribute
      def initialize(bound_definition)
        if bound_definition.kind_of?(Array)
          @assigner = ArrayAssigner.new(bound_definition)
        else
          @assigner = ValueAssigner.new(bound_definition)
        end
      end

      def assign_to(target_attribute, bound_arguments)
        target_attribute.assign @assigner.resolve(bound_arguments)
      end

      class ArrayAssigner
        def initialize(definitions)
          @bound_class = definitions.first
        end

        def resolve(arguments_list)
          raise ArgumentError.new("Expected #{arguments_list.inspect} to be an array") unless arguments_list.kind_of? Array
          arguments_list.map do |arguments|
            @bound_class.new(arguments)
          end
        end
      end

      class ValueAssigner
        def initialize(definition)
          @bound_class = definition
        end

        def resolve(arguments)
          @bound_class.new(arguments)
        end
      end
    end


    class << self
      attr_accessor :attrs

      def initialize_values
        self.attrs = {}
      end

      def set_attributes(*attributes)
        if attributes.any? { |a| !a.kind_of? Symbol }
          raise ArgumentError.new("Invalid list of attributes: #{attributes.inspect}")
        end

        attributes.each do |attribute|
          self.attrs[attribute] = RequiredAttribute
        end

        define_attribute_readers attributes
        define_attribute_writers attributes

        self
      end

      def optional(*optionals)
        if optionals.any? { |a| !a.kind_of? Symbol }
          raise ArgumentError.new("Invalid list of optional attributes: #{optionals.inspect}")
        end

        optionals.each do |attribute|
          self.attrs[attribute] = Attribute
        end

        define_attribute_readers optionals
        define_attribute_writers optionals

        self
      end

      def nested(nested_attributes)
        attributes = nested_attributes.keys

        attributes.each do |attribute|
          self.attrs[attribute] = RequiredAttribute
        end

        define_attribute_readers attributes
        define_nested_attribute_writers nested_attributes

        self
      end

      alias :build :new

      private

      def define_attribute_readers(attributes)
        attributes.each do |attribute|
          define_method attribute do
            get_attribute(attribute).value
          end
        end
      end

      def define_attribute_writers(attributes)
        attributes.each do |attribute|
          define_method :"#{attribute}=" do |value|
            get_attribute(attribute).assign value
          end
        end
      end

      def define_nested_attribute_writers(nested_attributes)
        attributes = nested_attributes.keys
        attributes.each do |attribute|
          define_method :"#{attribute}=" do |value|
            bound_definition = nested_attributes[attribute]
            get_attribute(attribute).assign_nested bound_definition, value
          end
        end
      end
    end

    def initialize(hash_or_object = {})
      seed hash_or_object
      validate!
    end


    def method_missing(meth, *args, &blk)
      attribute = meth.to_s.gsub(/=$/, '')
      raise ArgumentError.new("Unknown attribute: #{attribute}")
    end

    def get_attributes
      self.class.attrs.keys.map do |attribute_name|
        get_attribute(attribute_name)
      end
    end

    def __attributes__
      puts "DEPRECATED: use get_attributes"
      get_attributes.map(&:name)
    end

    private

    def get_attribute(attribute_name)
      attribute_class = self.class.attrs[attribute_name]

      var = :"@#{attribute_name}"
      attribute = instance_variable_get(var)

      unless attribute
        attribute = instance_variable_set(var, attribute_class.new(attribute_name))
      end

      attribute
    end

    def validate!
      get_attributes.each do |attribute|
        raise ArgumentError.new("Missing attribute: #{attribute.name}") unless attribute.valid?
      end
    end

    def seed(hash_or_object)
      case hash_or_object
      when Hash
        seeder = HashSeeder.new(self)
      else
        seeder = ObjectSeeder.new(self)
      end

      seeder.seed(hash_or_object)
    end
  end

  class HashSeeder
    def initialize(receiver)
      @receiver = receiver
    end

    def seed(hash)
      hash.each do |key, value|
        @receiver.public_send "#{key}=", value
      end
    end
  end

  class ObjectSeeder
    def initialize(receiver)
      @receiver = receiver
    end

    def seed(object)
      @receiver.get_attributes.each do |attribute|
        begin
          value = attribute.call_on(object)
        rescue NoMethodError => e
          value = nil
          raise ArgumentError, "missing #{attribute.name}" if attribute.required?
        end

        @receiver.public_send "#{attribute.name}=", value
      end
    end
  end
end
