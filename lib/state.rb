# frozen_string_literal: true

# State is the application's shared, observable property bag: which view the
# window shows, which web view is in front, and the list of tab ids.
#
# Ported from upstream's src/state.js, which mixes GJS's `addSignalMethods`
# into a plain object and emits `notify::<property>`. Ruby needs no mixin for
# that: the handlers are blocks held per property, and `set` calls the ones
# whose property changed.
class State
  def initialize
    @properties = {}
    @handlers = {}
  end

  def get(property) = @properties[property.to_s]

  # Takes a hash of properties, the way upstream's `set({ view: "tabs" })`
  # does, and tells the property's observers the new and previous values.
  # A property set to nil is a property cleared; one left out is untouched,
  # which is what upstream's `undefined` check means.
  def set(properties)
    properties.each do |property, value|
      key = property.to_s
      previous = @properties[key]
      @properties[key] = value
      notify_handlers(key, value, previous)
    end

    self
  end

  # Calls the block on every later change, with the new value and the previous
  # one — upstream's `notify`.
  def notify(property, &handler)
    @handlers[property.to_s] ||= []
    @handlers[property.to_s] << handler
    handler
  end

  # Keeps a target's property in step with one of ours, passing the value
  # through the block first — upstream's `bind`, which stands in for
  # GObject's bind_property between an object that is not a GObject and one
  # that is. A property that has never been set leaves the target alone.
  def bind(property, target, target_property, &transform)
    assignment(target, target_property, transform).then do |assign|
      assign.call(get(property))
      notify(property) { |value| assign.call(value) }
    end

    target
  end

  private

    # The one-argument assignment `bind` performs now and on every change. A
    # property that has never been set leaves the target alone.
    def assignment(target, target_property, transform)
      lambda do |value|
        unless value.nil?
          target.set_property(
            target_property.to_s.tr('_', '-'),
            transformed(value, transform),
          )
        end
      end
    end

    def transformed(value, transform)
      if transform
        transform.call(value)
      else
        value
      end
    end

    def notify_handlers(key, value, previous)
      @handlers[key].to_a.each { |handler| handler.call(value, previous) }
    end
end
