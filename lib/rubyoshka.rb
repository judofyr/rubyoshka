# frozen_string_literal: true

require 'modulation/gem'
require 'escape_utils'

export_default :Rubyoshka

# A Rubyoshka is a template representing a piece of HTML
class Rubyoshka
  # A Rendering is a rendering of a Rubyoshka
  class Rendering
    attr_reader :context
  
    # Initializes attributes and renders the given block
    # @param context [Hash] rendering context
    # @param block [Proc] template block
    # @return [void]
    def initialize(context, &block)
      @context = context
      @buffer = +''
      instance_eval(&block)
    end
  
    # Returns the result of the rendering
    # @return [String]
    def to_s
      @buffer
    end
  
    S_TAG_METHOD = <<~EOF
      def %1$s(*args, &block)
        tag(:%1$s, *args, &block)
      end
    EOF

    R_CONST_SYM = /^[A-Z]/
  
    # Catches undefined tag method call and handles them by defining the method
    # @param sym [Symbol] HTML tag or component identifier
    # @param args [Array] method call arguments
    # @param block [Proc] block passed to method call
    # @return [void]
    def method_missing(sym, *args, &block)
      value = @local && @local[sym]
      return value if value

      if sym =~ R_CONST_SYM
        o = instance_eval(sym.to_s) rescue Rubyoshka.const_get(sym) \
            rescue Object.const_get(sym)
        case o
        when ::Proc
          self.class.define_method(sym) { |*a, &b| emit(o.(*a, &b)) }
          emit(o.(*args, &block))
        when Rubyoshka
          self.class.define_method(sym) { |**ctx|
            ctx.empty? ? emit(o) : with(ctx) { emit(o) }
          }
          ctx = args.first
          Hash === ctx ? with(ctx) { emit(o) } : emit(o)
        when ::String
          @buffer << o
        else
          e = StandardError.new "Cannot render #{o.inspect}"
          e.set_backtrace(caller)
          raise e
        end
      else
        self.class.class_eval(S_TAG_METHOD % sym)
        tag(sym, *args, &block)
      end
    end
  
    # Emits the given object into the rendering buffer
    # @param o [Proc, Rubyoshka, String] emitted object
    # @return [void]
    def emit(o)
      case o
      when ::Proc
        instance_eval(&o)
      when Rubyoshka
        instance_eval(&o.block)
      when nil
      else
        @buffer << o.to_s
      end
    end
    alias_method :e, :emit
  
    S_LT              = '<'
    S_GT              = '>'
    S_LT_SLASH        = '</'
    S_SPACE_LT_SLASH  = ' </'
    S_SLASH_GT        = '/>'
    S_SPACE           = ' '
    S_EQUAL_QUOTE     = '="'
    S_QUOTE           = '"'

    E = EscapeUtils
  
    # Emits an HTML tag
    # @param sym [Symbol] HTML tag
    # @param text [String] text content of tag
    # @param props [Hash] tag attributes
    # @param block [Proc] nested HTML block
    # @return [void]
    def tag(sym, text = nil, **props, &block)
      sym = sym.to_s
  
      @buffer << S_LT << sym
      emit_props(props) unless props.empty?
  
      if block
        @buffer << S_GT
        instance_eval(&block)
        @buffer << S_LT_SLASH << sym << S_GT
      elsif Rubyoshka === text
        @buffer << S_GT
        emit(text)
        @buffer << S_LT_SLASH << sym << S_GT
      elsif text
        @buffer << S_GT << E.escape_html(text.to_s) <<
          S_LT_SLASH << sym << S_GT
      else
        @buffer << S_SLASH_GT
      end
    end

    # Emits tag attributes into the rendering buffer
    # @param props [Hash] tag attributes
    # @return [void]
    def emit_props(props)
      props.each { |k, v|
        case k
        when :text
        when :src, :href
          @buffer << S_SPACE << k.to_s << S_EQUAL_QUOTE <<
            E.escape_uri(v) << S_QUOTE
        else
          if v == true
            @buffer << S_SPACE << k.to_s
          else
            @buffer << S_SPACE << k.to_s << S_EQUAL_QUOTE << v << S_QUOTE
          end
        end
      }
    end

    # Emits the p tag
    # @param text [String] text content of tag
    # @param props [Hash] tag attributes
    # @para block [Proc] nested HTML block
    # @return [void]
    def p(text = nil, **props, &block)
      tag(:p, text, **props, &block)
    end
  
    S_HTML5_DOCTYPE = '<!DOCTYPE html>'
  
    # Emits an HTML5 doctype tag and an html tag with the given block
    # @param block [Proc] nested HTML block
    # @return [void]
    def html5(&block)
      @buffer << S_HTML5_DOCTYPE
      self.html(&block)
    end

    # Emits text into the rendering buffer
    # @param data [String] text
    def text(data)
      @buffer << E.escape_html(data)
    end

    # Sets a local context for the given block
    # @param ctx [Hash] context hash
    # @param block [Proc] nested HTML block
    # @return [void]
    def with(**ctx, &block)
      old_local, @local = @local, ctx
      instance_eval(&block)
    ensure
      @local = old_local
    end
  end

  attr_reader :block

  # Initializes a Rubyoshka with the given block
  # @param ctx [Hash] local context
  # @param block [Proc] nested HTML block
  # @param [void]
  def initialize(**ctx, &block)
    @block = ctx.empty? ? block : proc { with(ctx, &block) }
  end

  # Renders the associated block and returns the string result
  # @param context [Hash] context
  # @return [String]
  def render(**context)
    Rendering.new(context, &block).to_s
  end
end

module ::Kernel
  # Convenience method for creating a new Rubyoshka
  # @param ctx [Hash] local context
  # @param block [Proc] nested block
  # @return [Rubyoshka] Rubyoshka template
  def H(**ctx, &block)
    Rubyoshka.new(ctx, &block)
  end
end