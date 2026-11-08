#!/usr/bin/env ruby
# frozen_string_literal: true

# Drives the window and the dialogs reachable from it: the main menu's about
# and shortcuts dialogs, the tabs-bar toggle, the tab editor, and the delete
# confirmation on top of it.
#
#   nix develop --command xvfb-run -a ruby test/drive_main_window.rb
#
# Screenshots land in tmp/shots.

require 'tmpdir'

root = Dir.mktmpdir('tangram-drive')
ENV['XDG_CONFIG_HOME'] = File.join(root, 'config')
ENV['XDG_DATA_HOME'] = File.join(root, 'data')
ENV['XDG_CACHE_HOME'] = File.join(root, 'cache')
ENV.delete('DEV')
ENV.delete('FLATPAK_ID')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'tangram'
require_relative 'gtk_driver'

deleted = []

GtkDriver.drive(Application.new, shots: 'tmp/shots') do |d, app|
  d.window { app.window.window }

  # Checks against `app.app`/`app.icon_theme`/`app.style_provider` directly,
  # not through the window — `Application`'s own job (application
  # id, the three app-level accelerators `Shortcuts#build` installs, the
  # icon search path, the PULSE_PROP env vars, the CSS provider) rather than
  # anything the window merely inherits by being built under it.
  d.step('the application itself is set up') do
    d.check('application id') { app.app.application_id == Application::APPLICATION_ID }
    d.check('quit is bound to Ctrl+Q') { app.app.get_accels_for_action('app.quit') == ['<Control>q'] }
    d.check('shortcuts is bound to Ctrl+?') do
      app.app.get_accels_for_action('app.shortcuts') == ['<Control>question']
    end
    d.check('the icon directory is on the icon theme search path') do
      app.icon_theme.search_path.include?(Application::ICON_PATH)
    end
    d.check('the PulseAudio stream properties are set') do
      ENV['PULSE_PROP_application.icon_name'] == 're.sonny.Tangram-symbolic' &&
        ENV['PULSE_PROP_media.role'] == 'video'
    end
    d.check('the style provider loaded style.css from data/') do
      app.style_provider.is_a?(Gtk::CssProvider) && File.read(Application::STYLE_PATH).include?('.tab-close-button')
    end
  end

  d.step('the window is up') do
    d.check('window presented') { app.window.window.visible? }
    d.check('titled Tangram') { app.window.window.title == 'Tangram' }
    d.check('the new-tab view is up on a first run') { app.window.view_new.status_page.title == 'Welcome to Tangram' }
    d.check('menu button carries the main menu') do
      app.window.view_tabs.menu_button_top.menu_model.n_items == 2
    end
    # GTK keeps default-width/height in step with the real size once the
    # window is on screen, which is what makes them the right pair to record.
    d.check('the geometry is recorded for the next run') do
      app.window.settings.remember_window_state(app.window.window)
      app.window.settings.get_int('window-width') == app.window.window.default_width &&
        app.window.settings.get_int('window-height') == app.window.window.default_height &&
        app.window.settings.get_boolean('window-maximized') == false
    end
    d.shot('01-window')
  end

  d.step('the about dialog opens') do
    app.app.lookup_action('about').activate(nil)
  end

  d.step('the about dialog is on screen') do
    d.check('a dialog is visible') { !app.window.window.visible_dialog.nil? }
    d.check('it is the about dialog') do
      app.window.window.visible_dialog == app.window.actions.about_dialog.dialog
    end
    d.check('debug info lists the engines') do
      app.window.actions.about_dialog.debug_info.lines.length == 6
    end
    d.shot('02-about')
    app.window.window.visible_dialog&.close
  end

  d.step('the shortcuts dialog opens') do
    app.app.lookup_action('shortcuts').activate(nil)
  end

  d.step('the shortcuts dialog is on screen') do
    d.check('it is the shortcuts dialog') do
      app.window.window.visible_dialog == app.window.actions.shortcuts_dialog.dialog
    end
    d.shot('03-shortcuts')
    app.window.window.visible_dialog&.close
  end

  d.step('the tabs bar toggle writes the setting') do
    app.app.lookup_action('tabs-bar').tap do |action|
      d.check('starts on, as the schema says') { action.state == true }
      action.change_state(GLib::Variant.new(false))
      d.check('the action follows') { action.state == false }
      d.check('the setting follows') { app.window.settings.get_boolean('tabs-bar') == false }
    end
  end

  instance = nil
  dialog = nil

  d.step('a tab opens its editor') do
    instance = app.window.instances.create(name: 'Example', url: 'https://example.org')
    dialog = InstanceDialog.new(
      instance:  instance,
      on_delete: ->(id) { deleted << id },
    )
    dialog.present(app.window.window)
  end

  d.step('the editor shows the tab') do
    d.check('the editor is visible') { app.window.window.visible_dialog == dialog.dialog }
    d.check('the name row is filled in') { dialog.name_row.text == 'Example' }
    d.check('the homepage row is filled in') { dialog.url_row.text == 'https://example.org' }
    d.check('the priority row defaults to Normal') { dialog.priority_row.selected.zero? }
    d.check('update is sensitive with a homepage') { dialog.button_save.sensitive? }
    d.shot('04-tab-editor', dialog.dialog)
  end

  d.step('an empty homepage makes update insensitive') do
    dialog.url_row.text = ''
    d.check('update went insensitive') { !dialog.button_save.sensitive? }
    dialog.url_row.text = 'https://example.com'
    d.check('update came back') { dialog.button_save.sensitive? }
  end

  d.step('saving writes the tab back') do
    dialog.name_row.text = 'Renamed'
    dialog.priority_row.selected = 3
    dialog.user_agent_row.text = 'Tangram test'
    dialog.button_save.activate
  end

  d.step('the tab kept what was typed') do
    d.check('name saved') { instance.name == 'Renamed' }
    d.check('homepage saved') { instance.url == 'https://example.com' }
    d.check('user agent saved') { instance.user_agent == 'Tangram test' }
    d.check('priority saved as urgent') { instance.notifications_priority == 3 }
    d.check('the settings hold it too') do
      Settings.instance(instance.id).get_string('name') == 'Renamed'
    end
    d.check('the editor closed itself') { app.window.window.visible_dialog.nil? }
  end

  d.step('the editor is reopened') do
    dialog.present(app.window.window)
  end

  # A tick apart: the alert presents itself into the editor dialog, which has
  # to be on screen before it can take anything on top of it.
  d.step('the delete confirmation opens over the editor') do
    dialog.button_delete.activate
  end

  d.step('the confirmation asks before deleting') do
    d.check('the alert is on top') { app.window.window.visible_dialog == dialog.delete_tab_dialog.dialog }
    d.check('it offers cancel and delete') do
      dialog.delete_tab_dialog.dialog.has_response?('cancel') && dialog.delete_tab_dialog.dialog.has_response?('delete')
    end
    d.check('delete is the destructive one') do
      dialog.delete_tab_dialog.dialog.get_response_appearance('delete') ==
        Adwaita::ResponseAppearance::DESTRUCTIVE
    end
    d.check('nothing deleted yet') { deleted.empty? }
    d.shot('05-delete-tab', dialog.delete_tab_dialog.dialog)
  end

  d.step('cancelling leaves the tab alone') do
    dialog.delete_tab_dialog.dialog.signal_emit('response', 'cancel')
    d.check('still not deleted') { deleted.empty? }
  end

  d.step('confirming deletes the tab') do
    dialog.delete_tab_dialog.dialog.signal_emit('response', 'delete')
  end

  d.step('the window reports the deletion') do
    d.check('the tab id was handed over') { deleted == [instance.id] }
    # The editor is force-closed from under the alert, so the alert is the
    # only dialog left; a real click on "Delete" closes that one itself.
    d.check('the editor was taken down with it') do
      app.window.window.visible_dialog != dialog.dialog
    end
    app.window.window.visible_dialog&.close
  end

  d.step('the window is back on its own') do
    d.check('no dialog left') { app.window.window.visible_dialog.nil? }
    d.shot('06-after-delete')
  end
end
