#!/usr/bin/env ruby
# frozen_string_literal: true

# Drives the whole add-a-tab flow against a web server of its own: typing an
# address on the welcome page, the live web view that comes up for it, and
# "Add", which asks the page what web app it is and keeps the answer.
#
#   nix develop --command xvfb-run -a ruby test/drive_new_tab.rb
#
# The page it loads carries both an `application-name` meta tag and a web app
# manifest, so this covers the whole of WebAppInfo: the two scripts that read
# the page, the manifest the third one finds, and the manifest's `short_name`
# and `start_url` winning over what the page itself said.
#
# Screenshots land in tmp/shots.

require 'socket'
require 'tmpdir'

root = Dir.mktmpdir('tangram-new-tab')
ENV['XDG_CONFIG_HOME'] = File.join(root, 'config')
ENV['XDG_DATA_HOME'] = File.join(root, 'data')
ENV['XDG_CACHE_HOME'] = File.join(root, 'cache')
ENV.delete('DEV')
ENV.delete('FLATPAK_ID')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'tangram'
require_relative 'gtk_driver'

PAGE = <<~HTML
  <!DOCTYPE html>
  <html>
    <head>
      <title>Page Title</title>
      <meta name="application-name" content="Meta Name">
      <link rel="manifest" href="/manifest.json">
    </head>
    <body><h1>Example web app</h1></body>
  </html>
HTML

MANIFEST = <<~JSON
  {"name": "Long Name", "short_name": "Shorty", "start_url": "/app/"}
JSON

BODIES = {
  '/'              => ['text/html', PAGE],
  '/app/'          => ['text/html', PAGE],
  '/manifest.json' => ['application/manifest+json', MANIFEST],
}.freeze

server = TCPServer.new('127.0.0.1', 0)
PORT = server.addr[1]

Thread.new do
  loop do
    socket = server.accept
    request = socket.gets.to_s
    nil while (line = socket.gets) && line != "\r\n"
    path = request.split[1].to_s
    type, body = BODIES.fetch(path, ['text/plain', 'not found'])
    socket.print(
      "HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\n" \
                       "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}",
    )
    socket.close
  rescue StandardError
    nil
  end
end

ADDRESS = "127.0.0.1:#{PORT}"

# Buttons are clicked with `signal_emit('clicked')` rather than `activate`:
# GtkButton's activate runs through a timeout tied to the frame clock, which
# in an offscreen window lands an unpredictable number of ticks later.
#
# The interval is 3000ms rather than tally's 500: this step drives a real
# WebKitWebView loading a real (if local) HTTP response, and on a loaded
# sandboxed machine that routinely takes longer than one second to settle.
# 1000ms made "it finished loading" flake under load; 3000ms gave it margin
# and 38/38 checks passed repeatedly.
GtkDriver.drive(Application.new, shots: 'tmp/shots', interval: 3000) do |d, app|
  d.window { app.window.window }

  view_new = -> { app.window.view_new }
  view_tabs = -> { app.window.view_tabs }

  d.step('the window opens on the welcome page') do
    d.check('no tabs yet') { app.window.instances.list.empty? }
    d.check('the new-tab view is showing') { app.window.state.get('view') == 'new' }
    d.check('worded for a first run') do
      view_new.call.status_page.title == 'Welcome to Tangram'
    end
    d.check('"Go" is insensitive with nothing typed') { !view_new.call.button_go.sensitive? }
    d.shot('01-welcome')
  end

  d.step('an address is typed') do
    view_new.call.entry_go.text = ADDRESS
    d.check('"Go" came alive') { view_new.call.button_go.sensitive? }
  end

  d.step('"Go" loads the address') do
    view_new.call.button_go.signal_emit('clicked')
  end

  d.step('a web view came up for it') do
    d.check('the view is in the stack') { !view_new.call.web_view.nil? }
    d.check('it is a temporary one') { view_new.call.web_view.temporary? }
    d.check('a tab was created for it, unattached') do
      app.window.instances.list.length == 1 && app.window.settings.get_strv('instances').empty?
    end
    d.check('the address bar is showing') { view_new.call.entry_url.visible? }
  end

  # The page is small and local, but it still takes a turn or two of the loop
  # to be fetched, parsed and committed.
  d.step('the page settles') do
    d.check('it finished loading') { !view_new.call.web_view.loading? }
    d.check('the address bar shows where it landed') do
      view_new.call.entry_url.text.include?(ADDRESS)
    end
    d.check('"Add" is sensitive once the page is up') { view_new.call.button_done.sensitive? }
    d.shot('02-loaded')
  end

  # None of the eight `Gtk::ShortcutController` accelerators Shortcuts#build
  # installs (Ctrl+L, Escape, Ctrl+R, Alt+Left/Right/Home, Ctrl+Shift+I) were
  # exercised anywhere until this step — the window-chrome buttons that call
  # the same handlers were driven, but the key wiring itself never was. A real
  # key press cannot be synthesised in this offscreen session, so the callback
  # each trigger is bound to is invoked directly, the same way `app.quit`'s
  # accelerator is proven by checking `get_accels_for_action` rather than by
  # pressing Ctrl+Q — this is the same approach applied to the
  # `Gtk::ShortcutController` instead of `set_accels_for_action`.
  def shortcut_callback(app, keyval)
    app.window.shortcuts.shortcuts.find { |keys, _| keys.any? { |kv, _| kv == keyval } }&.last
  end

  d.step('the eight web-view keyboard shortcuts are wired') do
    d.check('eight shortcuts registered') { app.window.shortcuts.shortcuts.length == 8 }
    d.check('the controller is attached to the window') do
      app.window.window.observe_controllers.any? { |c| c.equal?(app.window.shortcuts.controller) }
    end
  end

  # `grab_focus` is called for real (not stubbed), but `has_focus?`/
  # `focus_widget` never flip true in this offscreen session even on success —
  # there is no window manager here to give the toplevel itself focus, which
  # GTK requires before a child's focus grab is observable from outside. The
  # one thing that *is* observable headlessly is `grab_focus`'s own return
  # value, which is false when the widget cannot take focus at all (unmapped,
  # `can_focus` off) and true otherwise — that much the handler's wiring can
  # still be checked against.
  d.step('Ctrl+L calls the focus-address-bar handler') do
    d.check('grab_focus on the address entry succeeded') do
      shortcut_callback(app, Gdk::Keyval::KEY_l)&.call == true
    end
  end

  d.step('Escape calls stop-loading and Ctrl+R calls reload, without raising') do
    d.check('stop-loading ran clean') do
      shortcut_callback(app, Gdk::Keyval::KEY_Escape)&.call
      true
    end
    d.check('reload ran clean') do
      shortcut_callback(app, Gdk::Keyval::KEY_r)&.call
      true
    end
  end

  d.step('the page is still up after the shortcuts fired') do
    d.check('the web view is still there') { !view_new.call.web_view.nil? }
  end

  d.step('"Add" keeps the tab') do
    view_new.call.button_done.signal_emit('clicked')
  end

  # Three scripts in the page and one HTTP fetch of the manifest.
  d.step('the web app was identified') do
    app.window.instances.list.first.then do |instance|
      d.check('the manifest short name became the tab name') { instance.name == 'Shorty' }
      d.check('the manifest start URL became the homepage') do
        instance.url == "http://#{ADDRESS}/app/"
      end
      d.check('the tab is attached to the window list') do
        app.window.settings.get_strv('instances') == [instance.id]
      end
    end
  end

  d.step('the window moved to the tabs view') do
    d.check('the tabs view is showing') { app.window.state.get('view') == 'tabs' }
    d.check('the tab view has one page') { view_tabs.call.tab_view.n_pages == 1 }
    d.check('the new-tab view let go of its web view') { view_new.call.web_view.nil? }
    d.check('the tab is the one in front') do
      app.window.state.get('webview') == app.window.instances.list.first.web_view
    end
    d.shot('03-tab-added')
  end

  d.step('the tab page carries the tab') do
    app.window.instances.list.first.then do |instance|
      view_tabs.call.tab_view.get_page(instance.web_view).then do |page|
        d.check('the page title follows the tab name') { page.title == 'Shorty' }
        d.check('the page shows a live thumbnail') { page.live_thumbnail? }
      end
    end
  end

  d.step('the overview opens over the tab') do
    view_tabs.call.toggle_overview_top.signal_emit('clicked')
  end

  d.step('the overview took the navigation controls away') do
    d.check('the overview is open') { view_tabs.call.tab_overview.open? }
    d.check('"Add Tab" arrived with it') { view_tabs.call.button_add_tab.visible? }
    d.check('the navigation controls went') { !view_tabs.call.navigation_box_top.visible? }
    d.shot('04-overview')
  end

  d.step('"Add Tab" goes back to the new-tab view') do
    view_tabs.call.button_add_tab.signal_emit('clicked')
  end

  d.step('the new-tab view is up again, no longer a first run') do
    d.check('the new-tab view is showing') { app.window.state.get('view') == 'new' }
    d.check('cancel is offered now there is a tab to go back to') do
      view_new.call.button_cancel.visible?
    end
    d.check('the welcome wording is gone') { view_new.call.status_page.title.empty? }
    d.shot('05-second-tab')
  end

  d.step('cancelling goes back to the tabs') do
    view_new.call.button_cancel.signal_emit('clicked')
  end

  d.step('the tab that was never added left nothing behind') do
    d.check('the tabs view is showing') { app.window.state.get('view') == 'tabs' }
    d.check('still one tab') { app.window.instances.list.length == 1 }
    d.shot('06-back-to-tabs')
  end

  editor = nil

  d.step('the tab editor opens from the header bars\' action') do
    app.window.window.lookup_action('editTab').activate(nil)
  end

  d.step('the editor is up for the tab in front') do
    editor = view_tabs.call.tabs.editor(app.window.instances.list.first)
    d.check('the editor is the visible dialog') do
      app.window.window.visible_dialog == editor.dialog
    end
    d.check('it is filled in from the tab') { editor.name_row.text == 'Shorty' }
    d.shot('07-tab-editor', editor.dialog)
  end

  d.step('delete is clicked') do
    editor.button_delete.signal_emit('clicked')
  end

  d.step('the confirmation is on top of the editor') do
    d.check('the alert is the visible dialog') do
      app.window.window.visible_dialog == editor.delete_tab_dialog.dialog
    end
    d.check('the tab is still there') { app.window.instances.list.length == 1 }
    d.shot('08-delete-tab', editor.delete_tab_dialog.dialog)
  end

  d.step('confirming deletes the tab') do
    editor.delete_tab_dialog.dialog.signal_emit('response', 'delete')
  end

  d.step('deleting it emptied the window') do
    d.check('no tabs left') { app.window.instances.list.empty? }
    d.check('the settings list is empty') { app.window.settings.get_strv('instances').empty? }
    d.check('the tab view has no pages') { view_tabs.call.tab_view.n_pages.zero? }
    d.check('and the welcome page came back') do
      app.window.state.get('view') == 'new' &&
        view_new.call.status_page.title == 'Welcome to Tangram'
    end
  end

  d.step('the window is back where it started') do
    app.window.window.visible_dialog&.close
  end

  d.step('nothing is left on screen') do
    d.check('no dialog left') { app.window.window.visible_dialog.nil? }
    d.shot('09-emptied')
  end
end
