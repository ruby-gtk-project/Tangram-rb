# frozen_string_literal: true

require 'adwaita'
require 'gobject-introspection'

require_relative 'tangram/rb/version'

# The engine versions the debug info lists come from the typelibs themselves,
# the way troll's `getGIRepositoryVersion` reads them.
module WebKit
end
unless WebKit.const_defined?(:WebView)
  GObjectIntrospection::Loader.load('WebKit', WebKit)
end

module Soup
end
unless Soup.const_defined?(:Session)
  GObjectIntrospection::Loader.load('Soup', Soup)
end

# AboutDialog is the dialog behind the main menu's "About Tangram".
#
# Ported from upstream's src/AboutDialog.js, with the three version helpers it
# imports from troll/src/util.js — `getGIRepositoryVersion`, `getGjsVersion`
# and `getGLibVersion` — folded in as `debug_info`. Upstream's GJS line
# becomes a Ruby line, and its GStreamer line is left out: this port has no
# GStreamer binding to ask, and inventing a number would be worse than
# listing one fewer. Upstream's `translator_credits` is left out for the same
# reason: it is a translated string, and the translations arrive with the po/
# setup.
#
# Upstream builds an Adw.AboutWindow, deprecated since libadwaita 1.6 in
# favour of Adw.AboutDialog, which is what this uses; the properties are the
# same ones.
class AboutDialog
  APPLICATION_NAME = 'Tangram'
  DEVELOPER_NAME = 'Sonny Piers'
  COPYRIGHT = '© 2019-2023 Sonny Piers'
  WEBSITE = 'https://tangram.sonny.re'
  ISSUE_URL = 'https://tangram.sonny.re/feedback'
  APPLICATION_ICON = 're.sonny.Tangram'

  DEVELOPERS = ['Sonny Piers https://sonny.re'].freeze

  DESIGNERS = [
    'Sonny Piers https://sonny.re',
    'Tobias Bernard <tbernard@gnome.org>',
  ].freeze

  ARTISTS = ['Tobias Bernard <tbernard@gnome.org>'].freeze

  CONTRIBUTORS = ['codyfish https://github.com/codyfish'].freeze

  # Memoized, like the dialog itself: upstream keeps one dialog for the whole
  # run, and a credit section added twice would be listed twice.
  def build
    @build ||= dialog.tap do |about|
      about.add_credit_section('Contributors', CONTRIBUTORS)
    end
  end

  # Upstream keeps one dialog and re-presents it; `present` takes the widget
  # the dialog belongs to, which replaces the transient-for it set by hand.
  def present(parent) = build.present(parent)

  def dialog
    @dialog ||= Adwaita::AboutDialog.new.tap do |about|
      about.application_name = APPLICATION_NAME
      about.developer_name = DEVELOPER_NAME
      about.copyright = COPYRIGHT
      about.license_type = Gtk::License::GPL_3_0_ONLY
      about.version = Tangram::Rb::VERSION
      about.website = WEBSITE
      about.application_icon = APPLICATION_ICON
      about.issue_url = ISSUE_URL
      about.debug_info = debug_info
      about.developers = DEVELOPERS
      about.designers = DESIGNERS
      about.artists = ARTISTS
    end
  end

  def debug_info
    [
      "WebKitGTK #{version_of(WebKit)}",
      "Ruby #{RUBY_VERSION}",
      "Adw #{Adwaita::VERSION_S}",
      "GTK #{Gtk::Version::STRING}",
      "GLib #{glib_version}",
      "libsoup #{soup_version}",
    ].join("\n")
  end

  private

    # The typelib's own version, as troll reads it off the repository.
    def version_of(namespace)
      [
        namespace::MAJOR_VERSION,
        namespace::MINOR_VERSION,
        namespace::MICRO_VERSION,
      ].join('.')
    end

    def glib_version
      [GLib::Version::MAJOR, GLib::Version::MINOR, GLib::Version::MICRO].join('.')
    end

    def soup_version
      [Soup.major_version, Soup.minor_version, Soup.micro_version].join('.')
    end
end
