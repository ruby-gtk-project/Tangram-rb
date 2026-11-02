# frozen_string_literal: true

require 'json'
require 'uri'

require 'gtk4'
require 'gobject-introspection'

require_relative 'web_view'

# JavaScriptCore is where the value an evaluated script answers with comes
# from; without its typelib loaded the bindings have no class to map the
# result of `evaluate_javascript_finish` onto.
module JSC
end
unless JSC.const_defined?(:Value)
  GObjectIntrospection::Loader.load('JavaScriptCore', JSC)
end

# Soup carries the HTTP session the manifest fetch uses. There is no
# ruby-gnome gem for libsoup 3, so the typelib is loaded into a module of our
# own; lib/url.rb loads the same one for its public-suffix lookup.
module Soup
end
unless Soup.const_defined?(:Session)
  GObjectIntrospection::Loader.load('Soup', Soup)
end

# WebAppInfo asks a page what web app it is: the name to give the tab and the
# address to treat as its homepage. It reads the page's own metadata first and
# then, if the page links a web app manifest, lets the manifest override both.
#
# Ported from upstream's src/webapp/webapp.js, with src/webapp/ephy.js — which
# upstream copied from Epiphany's web-process extension — folded in as the
# three scripts below. Upstream serialises each of those JavaScript functions
# with `fn.toString()` and evaluates `(${fn})()` in the page; here they are
# written out as the self-calling expressions that produces, which is the same
# code reaching the page by a shorter route.
#
# Upstream's `getWebAppIcon` and `findBestIcon` are left out. They are dead
# upstream: every call site is commented out, the icon is never put on the
# info object, and nothing reads it.
#
# Upstream's chain of `await`s becomes a chain of callbacks, because the Ruby
# bindings expose GIO's asynchronous calls as a method plus a completion
# block rather than as promises. The shape is the same: title, then URL, then
# the manifest URL, then the manifest itself, and `fetch` calls the block it
# was given once with the finished info.
class WebAppInfo
  TITLE_SCRIPT = <<~JAVASCRIPT
    (function () {
      const metas = document.head.getElementsByTagName("meta");
      for (let i = 0; i < metas.length; i++) {
        const meta = metas[i];
        if (meta.name === "application-name") return meta.content;
        if (meta.name === "apple-mobile-web-app-title") return meta.content;
        if (
          meta.getAttribute("property") === "og:site_name" ||
          meta.name === "og:site_name"
        )
          return meta.content;
      }
      const titles = document.head.getElementsByTagName("title");
      const title = titles[titles.length - 1];
      if (title && title.innerText) return title.innerText;
      return document.location.hostname;
    })()
  JAVASCRIPT

  URL_SCRIPT = <<~JAVASCRIPT
    (function () {
      function querySelectorLast(el, query) {
        const els = el.querySelectorAll(query);
        return els[els.length - 1];
      }

      const msApplicationStartURL = querySelectorLast(
        document.head,
        "meta[name=msapplication-starturl]",
      );
      if (msApplicationStartURL && msApplicationStartURL.content) {
        return msApplicationStartURL.content;
      }

      const openGraphURL = querySelectorLast(
        document.head,
        "meta[property='og:url']",
      );
      if (openGraphURL && openGraphURL.content) {
        return openGraphURL.content;
      }

      return document.location.href;
    })()
  JAVASCRIPT

  MANIFEST_SCRIPT = <<~JAVASCRIPT
    (function () {
      const manifest = document.head.querySelector("link[rel=manifest]");
      return manifest ? manifest.href : null;
    })()
  JAVASCRIPT

  # Calls the block once with a hash carrying `:title`, `:url` and, when the
  # page links one, `:manifest`.
  def self.fetch(web_view, &on_info) = new(web_view).fetch(&on_info)

  def initialize(web_view)
    @web_view = web_view
  end

  attr_reader :web_view

  def fetch(&on_info)
    evaluate(TITLE_SCRIPT, web_view.title) do |title|
      evaluate(URL_SCRIPT, web_view.uri) do |url|
        evaluate(MANIFEST_SCRIPT, nil) do |manifest_url|
          with_manifest(info(title, url), manifest_url, &on_info)
        end
      end
    end
  end

  def session = @session ||= Soup::Session.new

  private

    # Runs the script in the page and calls the block with the string it
    # answered with, falling back to the value the web view itself reports
    # when the page has nothing to say or the script could not be run.
    def evaluate(script, fallback, &on_value)
      web_view.evaluate_javascript(
        script,
        -1,
        nil,
        nil,
        nil,
      ) do |_view, result|
        on_value.call(string_value(result) || fallback)
      end
    end

    def string_value(result)
      web_view.evaluate_javascript_finish(result).then do |value|
        if value.string?
          value.to_string_as_bytes.to_s
        end
      end
    rescue StandardError => error
      warn("web app info: #{error.message}")
      nil
    end

    # What the page itself said, before any manifest is consulted. An address
    # the page gave as a relative one is resolved against the page's own.
    def info(title, url)
      {title: title}.tap do |fields|
        unless url.to_s.empty?
          fields[:url] = resolve(url)
        end
      end
    end

    def with_manifest(info, manifest_url, &on_info)
      if manifest_url.to_s.empty?
        on_info.call(info)
      else
        fetch_manifest(manifest_url) { |manifest| on_info.call(merge(info, manifest)) }
      end
    end

    # The manifest's short name wins over its name, which wins over whatever
    # the page's own metadata said, and its start URL replaces the page's.
    def merge(info, manifest)
      if manifest.nil?
        info
      else
        merged(info, manifest)
      end
    end

    def merged(info, manifest)
      info.dup.tap do |fields|
        name = manifest['short_name'] || manifest['name']

        unless name.to_s.empty?
          fields[:title] = name
        end

        unless manifest['start_url'].to_s.empty?
          fields[:url] = resolve(manifest['start_url'])
        end

        fields[:manifest] = manifest
      end
    end

    def fetch_manifest(url, &on_manifest)
      if url.start_with?('data:')
        on_manifest.call(parse(data_uri_bytes(url)))
      else
        request(url, &on_manifest)
      end
    end

    def request(url, &on_manifest)
      message(url).then do |request|
        if request
          send_request(request, &on_manifest)
        else
          on_manifest.call(nil)
        end
      end
    end

    def send_request(request, &on_manifest)
      session.send_and_read_async(request, GLib::PRIORITY_DEFAULT, nil) do |_session, result|
        on_manifest.call(parse(response_bytes(result)))
      end
    end

    # The tab's own user agent goes out with the request, so a site that
    # serves a different manifest per client serves the one the tab will see.
    def message(url)
      Soup::Message.new('GET', url).tap do |request|
        request.request_headers.append('Cache-Control', 'no-cache')
        request.request_headers.append('User-Agent', web_view.settings.user_agent.to_s)
      end
    rescue StandardError => error
      warn("web app manifest: #{error.message}")
      nil
    end

    def response_bytes(result)
      session.send_and_read_finish(result)
    rescue StandardError => error
      warn("web app manifest: #{error.message}")
      nil
    end

    def data_uri_bytes(url)
      Soup.uri_decode_data_uri(url).first
    rescue StandardError => error
      warn("web app manifest: #{error.message}")
      nil
    end

    # A manifest that is missing, truncated or not JSON at all leaves the
    # page's own metadata standing, which is what upstream's `logError` and
    # `return null` amount to.
    def parse(bytes)
      if bytes.nil?
        nil
      else
        JSON.parse(bytes.to_s)
      end
    rescue JSON::ParserError => error
      warn("web app manifest: #{error.message}")
      nil
    end

    # GLib's URI parser, and with it `g_uri_resolve_relative`, is not bound in
    # ruby-gnome; Ruby's own URI joins a relative reference to a base the same
    # way, and an address it cannot parse is passed through unchanged.
    def resolve(url)
      URI.join(web_view.uri.to_s, url).to_s
    rescue StandardError
      url
    end
end
