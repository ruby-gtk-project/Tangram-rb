# frozen_string_literal: true

require 'gtk4'
require 'adwaita'
require 'gobject-introspection'

require_relative 'tangram/rb/version'

# WebKit carries the engine every tab runs in. There is no ruby-gnome gem for
# WebKitGTK 6, so the typelib is loaded straight into a module of our own, the
# way lib/url.rb loads Soup's.
module WebKit
end
unless WebKit.const_defined?(:WebView)
  GObjectIntrospection::Loader.load('WebKit', WebKit)
end

# TabWebView is the web view widget itself.
#
# It exists as a subclass of WebKit::WebView for two reasons. The first is that
# `network-session`, `web-context` and `user-content-manager` are
# construct-only properties, and the Ruby bindings generate
# `WebKit::WebView#initialize` from the typelib's one constructor —
# `webkit_web_view_new()`, which takes no arguments — so there is no way to
# hand those three objects to a plain `WebKit::WebView.new`. A Ruby subclass
# that calls `type_register` gets GObject's own property-hash constructor
# instead, which passes them to g_object_new where construct-only properties
# are accepted. The second is that upstream hangs two values off each view —
# `webview.instance_id` and `webview.mode` — which a subclass can simply
# declare.
#
# The two modes are upstream's src/constants.js, folded in here because they
# describe nothing but a web view: TEMPORARY while the tab is still being set
# up in the new-tab view, PERMANENT once "Add" has been clicked.
class TabWebView < WebKit::WebView
  TEMPORARY = 'TEMPORARY'
  PERMANENT = 'PERMANENT'

  type_register

  attr_accessor :instance_id, :mode

  # A tab still being set up may navigate anywhere; see Url's
  # `allowed_for_navigation?`.
  def temporary? = mode == TEMPORARY
end

# WebView builds one tab's web view: its own network session, so each tab's
# cookies and storage are its own, its own web context, the settings the tab's
# user agent is applied to, and the navigation, notification and download
# policy around it.
#
# Ported from upstream's src/WebView.js, with src/constants.js folded into
# TabWebView above.
#
# Three pieces of upstream's file are deliberately left out rather than
# approximated.
#
# The first is the `tangram-resource` URI scheme, which serves files out of
# upstream's GResource bundle; this port ships no resource bundle, so a scheme
# handler would have nothing to answer with.
#
# The second is the commented-out web inspector block, which is dead upstream
# too — the inspector is reached through the window's `<Control><Shift>I`
# instead.
#
# The third is upstream's `initialize-notification-permissions` handler, which
# pre-grants the notification permission for the tab's own origin so the web
# app never has to ask. `webkit_web_context_initialize_notification_permissions`
# takes two GLists of WebKitSecurityOrigin, and the Ruby binding segfaults
# converting a list with an origin in it (an empty list is fine), so there is
# no way to call it. Nothing is lost: `permission-request` below allows every
# notification permission request outright, which is the state upstream's call
# is reaching for.
class WebView
  APPLICATION_NAME = 'Tangram'

  # `on_notification` takes a WebKit notification and the tab's id; the window
  # turns it into a Gio notification.
  def initialize(instance:, window:, on_notification:, mode: TabWebView::PERMANENT)
    @instance = instance
    @window = window
    @on_notification = on_notification
    @mode = mode
  end

  attr_reader :instance, :window

  def build
    @build ||= widget.tap do |view|
      network_session.signal_connect('download-started') do |_session, download|
        start_download(download)
      end

      instance.observe('user-agent') { |agent| apply_user_agent(web_settings, agent) }

      view.signal_connect('create') do |_view, navigation_action|
        on_create(navigation_action)
      end

      view.signal_connect('permission-request') do |_view, request|
        answer_permission_request(request)
        false
      end

      view.signal_connect('show-notification') do |_view, notification|
        @on_notification.call(notification, instance.id)
        true
      end

      view.signal_connect('decide-policy') do |_view, decision, decision_type|
        on_decide_policy(decision, decision_type)
      end

      # A tab being set up has no homepage yet; the new-tab view loads the
      # address the user typed as soon as it has one.
      unless instance.url.empty?
        view.load_uri(instance.url)
      end
    end
  end

  def widget
    @widget ||= TabWebView.new(
      network_session:      network_session,
      web_context:          web_context,
      settings:             web_settings,
      user_content_manager: user_content_manager,
    ).tap do |view|
      view.instance_id = instance.id
      view.mode = @mode
    end
  end

  # One session per tab, rooted at the tab's own two directories, which is
  # what keeps each web app's cookies, storage and cache to itself.
  def network_session
    @network_session ||= WebKit::NetworkSession.new(instance.data_dir, instance.cache_dir).tap do |session|
      session.set_tls_errors_policy(WebKit::TLSErrorsPolicy::FAIL)
      session.website_data_manager.favicons_enabled = true

      session.cookie_manager.tap do |cookies|
        cookies.set_accept_policy(WebKit::CookieAcceptPolicy::NO_THIRD_PARTY)
        cookies.set_persistent_storage(
          File.join(instance.data_dir, 'cookies.sqlite'),
          WebKit::CookiePersistentStorage::SQLITE,
        )
      end
    end
  end

  def web_context
    @web_context ||= WebKit::WebContext.new.tap do |context|
      context.set_spell_checking_enabled(true)
      context.set_spell_checking_languages(GLib.language_names)
      context.add_path_to_sandbox(instance.data_dir, true)
      context.add_path_to_sandbox(instance.cache_dir, true)
    end
  end

  # The comment upstream leaves on `enable_back_forward_navigation_gestures`
  # and the three settings after it points at Epiphany's embed prefs, which is
  # where it took them from.
  def web_settings
    @web_settings ||= WebKit::Settings.new.tap do |settings|
      settings.enable_smooth_scrolling = true
      settings.media_playback_requires_user_gesture = true
      settings.enable_back_forward_navigation_gestures = true
      settings.enable_developer_extras = true
      settings.javascript_can_open_windows_automatically = true
      settings.allow_top_navigation_to_data_urls = false

      apply_user_agent(settings, instance.user_agent)
    end
  end

  def user_content_manager = @user_content_manager ||= WebKit::UserContentManager.new

  private

    # A tab with no user agent of its own presents the application's own,
    # which is what WebKit builds from the application details.
    #
    # The settings object is passed in rather than read back off
    # `web_settings`, because this is called from inside that method's own
    # `tap` — where the memoized value is not assigned yet.
    def apply_user_agent(settings, agent)
      if agent.to_s.empty?
        settings.set_user_agent_with_application_details(APPLICATION_NAME, Tangram::Rb::VERSION)
      else
        settings.user_agent = agent
      end
    end

    # A window the page asks to open: a tab still being set up follows it
    # itself, so the user can browse to the address of the web app; an added
    # tab hands it to the browser.
    def on_create(navigation_action)
      navigation_action.request.uri.then do |request_url|
        if widget.temporary?
          widget.load_uri(request_url)
        else
          show_in_browser(request_url)
        end
      end
    end

    def answer_permission_request(request)
      if request.is_a?(WebKit::NotificationPermissionRequest)
        request.allow
      else
        request.deny
      end
    end

    # A middle click, or a click with Control held, means the user asked for
    # the browser rather than the tab.
    def on_decide_policy(decision, decision_type)
      if decision_type == WebKit::PolicyDecisionType::NAVIGATION_ACTION
        decide_navigation(decision, decision.navigation_action)
      else
        false
      end
    end

    def decide_navigation(decision, navigation_action)
      if open_in_browser?(navigation_action)
        decision.ignore
        show_in_browser(navigation_action.request.uri)
        true
      else
        false
      end
    end

    def open_in_browser?(navigation_action)
      control = Gdk::ModifierType::CONTROL_MASK.to_i

      navigation_action.mouse_button == Gdk::BUTTON_MIDDLE ||
        (navigation_action.modifiers.to_i & control) == control
    end

    # ruby-gnome's `Gtk.show_uri` wrapper still names the parent window
    # `screen`, after the GTK3 signature it was written for; GTK4 passes it
    # straight through as the parent.
    def show_in_browser(uri)
      Gtk.show_uri(
        screen:    window,
        uri:       uri,
        timestamp: Gdk::CURRENT_TIME,
      )
    end

    # Beware of https://bugs.webkit.org/show_bug.cgi?id=201868, which is why
    # overwriting is refused rather than allowed.
    #
    # An http download goes to the browser, which has the UI for it. blob: and
    # file: URIs cannot be handed to another application, so those are saved
    # here; they are quick enough that no progress UI is needed.
    def start_download(download)
      download.allow_overwrite = false

      download.request.uri.then do |uri|
        if uri.start_with?('http')
          download.cancel
          Gio::AppInfo.launch_default_for_uri(uri, nil)
        else
          save_download(download)
        end
      end
    end

    def save_download(download)
      download.signal_connect('failed') do |_download, error|
        warn("download failed: #{error.message}")
      end

      download.signal_connect('decide-destination') do |_download, suggested_filename|
        choose_destination(download, suggested_filename)
      end
    end

    def choose_destination(download, suggested_filename)
      save_dialog(suggested_filename).save(window, nil) do |dialog, result|
        destination(dialog, result).then do |path|
          if path
            download.destination = path
          else
            download.cancel
          end
        end
      end

      true
    end

    def destination(dialog, result)
      dialog.save_finish(result)&.path
    rescue StandardError
      nil
    end

    # "unknown.asc" is WebKit's placeholder for a download it could not name,
    # and is no better a suggestion than none at all.
    def save_dialog(suggested_filename)
      Gtk::FileDialog.new.tap do |dialog|
        dialog.title = 'Save File'
        dialog.initial_name = usable_filename(suggested_filename)

        download_folder.then do |folder|
          if folder
            dialog.initial_folder = folder
          end
        end
      end
    end

    def usable_filename(suggested_filename)
      if suggested_filename.to_s.empty? || suggested_filename == 'unknown.asc'
        ''
      else
        suggested_filename
      end
    end

    def download_folder
      GLib.get_user_special_dir(GLib::UserDirectory::DIRECTORY_DOWNLOAD).then do |path|
        if path
          Gio::File.new_for_path(path)
        end
      end
    end
end
