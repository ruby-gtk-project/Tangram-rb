# frozen_string_literal: true

require 'gtk4'

# Shortcuts is the window's keyboard navigation: the accelerators that drive
# the page in front, plus the three application accelerators.
#
# Ported from upstream's src/Shortcuts.js. Upstream hands each accelerator to
# `Gtk.ShortcutTrigger.parse_string`, which is not bound in ruby-gnome, so the
# triggers are built from the keyval and modifiers that function would have
# parsed out. GTK's own parser lowercases a letter and adds Shift, which is
# why `<Control><Shift>R` is the `r` keyval with both modifiers rather than
# the `R` one.
class Shortcuts
  NONE = 0
  ALT = Gdk::ModifierType::ALT_MASK.to_i
  CONTROL = Gdk::ModifierType::CONTROL_MASK.to_i
  SHIFT = Gdk::ModifierType::SHIFT_MASK.to_i

  # The accelerators upstream sets for application actions. `app.inspector` is
  # upstream's: no action of that name is ever added, so the accelerator does
  # nothing — but it is what upstream registers, and dropping it would be a
  # change to the port rather than a port of the file.
  ACCELERATORS = {
    'app.quit'      => ['<Primary>Q'],
    'app.inspector' => ['<Primary><Shift>D'],
    'app.shortcuts' => ['<Primary>question'],
  }.freeze

  def initialize(
    window:,
    application:,
    on_reload:,
    on_stop_loading:,
    on_go_back:,
    on_go_forward:,
    on_go_home:,
    on_toggle_web_inspector:,
    on_focus_address_bar:
  )
    @window = window
    @application = application
    @on_reload = on_reload
    @on_stop_loading = on_stop_loading
    @on_go_back = on_go_back
    @on_go_forward = on_go_forward
    @on_go_home = on_go_home
    @on_toggle_web_inspector = on_toggle_web_inspector
    @on_focus_address_bar = on_focus_address_bar
  end

  attr_reader :window, :application

  def build
    @build ||= controller.tap do |shortcut_controller|
      shortcuts.each do |keys, callback|
        shortcut_controller.add_shortcut(shortcut(keys, callback))
      end

      ACCELERATORS.each do |action, accelerators|
        application.set_accels_for_action(action, accelerators)
      end

      window.add_controller(shortcut_controller)
    end
  end

  def controller = @controller ||= Gtk::ShortcutController.new

  # Each entry is the list of key/modifier pairs the accelerator was written
  # with, and what pressing any of them does.
  def shortcuts
    [
      [[[Gdk::Keyval::KEY_Home, ALT]], @on_go_home],
      [[[Gdk::Keyval::KEY_Escape, NONE]], @on_stop_loading],
      [[[Gdk::Keyval::KEY_r, CONTROL], [Gdk::Keyval::KEY_F5, NONE]], reload(bypass_cache: false)],
      [
        [[Gdk::Keyval::KEY_r, CONTROL | SHIFT], [Gdk::Keyval::KEY_F5, SHIFT]],
        reload(bypass_cache: true),
      ],
      [[[Gdk::Keyval::KEY_Left, ALT]], @on_go_back],
      [[[Gdk::Keyval::KEY_Right, ALT]], @on_go_forward],
      [[[Gdk::Keyval::KEY_i, CONTROL | SHIFT]], @on_toggle_web_inspector],
      [[[Gdk::Keyval::KEY_l, CONTROL]], @on_focus_address_bar],
    ]
  end

  private

    def reload(bypass_cache:)
      -> { @on_reload.call(bypass_cache) }
    end

    # The callback's answer is thrown away and the shortcut reports that it
    # handled the key, which is what upstream's `fn(); return true;` does.
    def shortcut(keys, callback)
      Gtk::Shortcut.new(trigger(keys), action(callback))
    end

    def action(callback)
      Gtk::CallbackAction.new do
        callback.call
        true
      end
    end

    # One accelerator is one trigger; several are folded into a chain of
    # alternatives, which is what upstream's `accels.join("|")` parses to.
    def trigger(keys)
      keys.map { |keyval, modifiers| Gtk::KeyvalTrigger.new(keyval, modifiers) }
        .reduce { |first, second| Gtk::AlternativeTrigger.new(first, second) }
    end
end
