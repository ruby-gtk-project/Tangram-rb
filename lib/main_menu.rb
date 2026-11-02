# frozen_string_literal: true

require 'adwaita'

# MainMenu is the menu behind the window's primary menu button: the tabs bar
# toggle, then a section with the shortcuts window and the about dialog.
#
# Ported from the `menu menu_app` block at the end of upstream's
# src/ViewTabs.blp, which both of that window's header bars point at.
class MainMenu
  def build
    menu.tap do |model|
      model.append('Show Tabs Bar', 'app.tabs-bar')

      help_section.tap do |section|
        section.append('Keyboard Shortcuts', 'app.shortcuts')
        section.append('About Tangram', 'app.about')
      end

      model.append_section(nil, help_section)
    end
  end

  def menu = @menu ||= Gio::Menu.new
  def help_section = @help_section ||= Gio::Menu.new
end
