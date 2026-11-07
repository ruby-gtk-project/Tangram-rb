# frozen_string_literal: true

require 'socket'
require 'securerandom'
require 'gtk4'

require 'web_app_info'

# Ported from upstream's src/webapp/test.js: all 9 scenarios, run the way
# upstream ran them — a real WebKit::WebView loading real HTTP responses from
# a local server, fed to `getWebAppInfo`/`WebAppInfo.fetch`, with the same
# assertions on the title and URL the fallback chain lands on.
#
# Needs GTK and WebKitGTK, which need a display:
#
#   nix develop --command xvfb-run -a ruby -e \
#     'require "rspec/core"; exit RSpec::Core::Runner.run(["spec/web_app_info_spec.rb"])'
#
# Upstream's last scenario (a full manifest overriding the page) is also
# covered indirectly by test/drive_new_tab.rb's step "the web app was
# identified"; it is repeated here so every scenario lives in one place and
# none of the 9 depends on a UI driver to exist.
RSpec.describe WebAppInfo do
  # One server for the whole file: each example registers its page (and,
  # if it has one, its manifest) under a path of its own, so examples never
  # share or clobber each other's response.
  before(:all) do
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @routes = {}

    @server_thread = Thread.new do
      loop do
        socket = @server.accept
        request = socket.gets.to_s
        nil while (line = socket.gets) && line != "\r\n"
        path = request.split[1].to_s
        content_type, body = @routes.fetch(path, ['text/plain', 'not found'])
        socket.print(
          "HTTP/1.1 200 OK\r\nContent-Type: #{content_type}\r\n" \
                           "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}",
        )
        socket.close
      rescue StandardError
        nil
      end
    end
  end

  after(:all) do
    @server.close
    @server_thread.kill
  end

  # Serves `html` (and `manifest`, if given) under a fresh path, loads it in
  # a fresh web view, runs `WebAppInfo.fetch` on it once the page has
  # settled, and answers the info hash it fetched.
  def fetch_info(html:, manifest: nil)
    base = "/#{SecureRandom.hex(8)}/"
    @routes[base] = ['text/html', html]
    if manifest
      @routes["#{base}manifest.json"] = ['application/manifest+json', manifest]
    end

    view = WebKit::WebView.new
    loop = GLib::MainLoop.new(nil, false)

    view.signal_connect('load-changed') do |_v, event|
      if event == WebKit::LoadEvent::FINISHED
        loop.quit
      end
    end
    view.load_uri("http://127.0.0.1:#{@port}#{base}")
    run_with_timeout(loop)

    info = nil
    WebAppInfo.fetch(view) do |fetched|
      info = fetched
      loop.quit
    end
    run_with_timeout(loop)

    info
  end

  def run_with_timeout(loop)
    watchdog = GLib::Timeout.add(5000) do
      loop.quit
      false
    end
    loop.run
    GLib::Source.remove(watchdog)
  end

  # Scenario 1: an `msapplication-starturl` meta is the first thing
  # `URL_SCRIPT` looks for, ahead of Open Graph and the page's own location.
  it 'prefers msapplication-starturl over the page location' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="msapplication-starturl" content="https://msapplication.starturl">
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:url]).to eq('https://msapplication.starturl')
  end

  # Scenario 2: with no title, no app-name meta and no manifest, the title
  # falls all the way back to the page's own hostname.
  it 'falls back to the hostname when nothing else names the page' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:title]).to eq('127.0.0.1')
  end

  # Scenario 3: an `og:url` meta (no manifest) wins over the page's own
  # location, same as `msapplication-starturl` did in scenario 1.
  it 'prefers og:url over the page location' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta property="og:url" content="https://opengraph.url">
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:url]).to eq('https://opengraph.url')
  end

  # Scenario 4: `application-name` wins over a `<title>` on the same page.
  it 'prefers the application-name meta over the title tag' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="application-name" content="meta-application-name">
        <title>title</title>
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:title]).to eq('meta-application-name')
  end

  # Scenario 5: `apple-mobile-web-app-title` wins over a `<title>` too.
  it 'prefers the apple-mobile-web-app-title meta over the title tag' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="apple-mobile-web-app-title" content="meta-apple-mobile-web-app-title">
        <title>title</title>
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:title]).to eq('meta-apple-mobile-web-app-title')
  end

  # Scenario 6: `og:site_name` (as a `property` attribute) wins over
  # `application-name`, which in turn would have won over the title tag.
  it 'prefers og:site_name (property) over application-name' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta property="og:site_name" content="meta-property-site-name">
        <title>title</title>
        <meta name="application-name" content="meta-application-name">
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:title]).to eq('meta-property-site-name')
  end

  # Scenario 7: when both the `name` and `property` variants of
  # `og:site_name` are present, `TITLE_SCRIPT`'s loop finds the `name` one
  # first (it only checks `meta.name`, then falls through to the attribute
  # check for `property`), so the `name` variant wins.
  it 'prefers og:site_name (name) over og:site_name (property) when both are present' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="og:site_name" content="meta-site-name">
        <meta property="og:site_name" content="meta-property-site-name">
        <title>title</title>
        <meta name="application-name" content="meta-application-name">
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:title]).to eq('meta-site-name')
  end

  # Scenario 8: with none of the name-ish metas present, the title falls
  # back to the `<title>` tag.
  it 'falls back to the title tag when no naming meta is present' do
    info = fetch_info(
      html: <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <title>title</title>
        </head>
        <body></body>
        </html>
      HTML
    )

    expect(info[:title]).to eq('title')
  end

  # Scenario 9: a linked manifest overrides both the page's title and URL —
  # its `short_name` beats its own `name`, and its `start_url` is resolved
  # against the page's own address.
  it 'lets a linked manifest override the page title and URL' do
    info = fetch_info(
      html:     <<~HTML,
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <link rel="manifest" href="manifest.json">
        <title>foobar</title>
        </head>
        <body></body>
        </html>
      HTML
      manifest: <<~JSON,
        {
          "name": "HackerWeb",
          "short_name": "HackerWeb",
          "start_url": "../startpoint.html?foo=bar#foobar",
          "display": "standalone",
          "background_color": "#fff",
          "description": "A simply readable Hacker News app.",
          "icons": [
            {"src": "images/touch/homescreen48.png", "sizes": "48x48", "type": "image/png"}
          ]
        }
      JSON
    )

    expect(info[:title]).to eq('HackerWeb')
    expect(info[:url]).to end_with('/startpoint.html?foo=bar#foobar')
  end
end
